// 悬浮窗状态：并行执行已启用的多个翻译服务，按服务维护结果；不负责持久化配置。
import AppKit
import Combine
import Foundation

struct ProviderResult: Identifiable, Equatable {
    let id: String
    let title: String
    var text = ""
    var isStreaming = false
    var error: String?
}

final class PopupViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var results: [ProviderResult] = []
    @Published var isTranslating = false
    @Published var errorMessage: String?
    @Published var didCopy = false
    @Published var focusToken = 0

    var primaryText: String {
        results.first(where: { !$0.text.isEmpty })?.text ?? ""
    }

    private let store: SettingsStore
    private let service: TranslationService
    private var task: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init(store: SettingsStore, service: TranslationService) {
        self.store = store
        self.service = service
    }

    func translate() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        task?.cancel()
        errorMessage = nil
        didCopy = false

        let config = store.config
        let apiKey = store.apiKey
        let baiduKey = store.baiduKey

        var planned: [ProviderResult] = []
        if config.llmEnabled {
            planned.append(ProviderResult(id: "llm", title: Self.llmTitle(config)))
        }
        if config.baiduEnabled {
            planned.append(ProviderResult(id: "baidu", title: "百度翻译"))
        }

        guard !planned.isEmpty else {
            results = []
            isTranslating = false
            errorMessage = "还没有启用翻译服务。请在设置中开启 AI 翻译或百度翻译。"
            return
        }

        results = planned
        isTranslating = true

        task = Task { @MainActor [weak self] in
            guard let self else { return }

            await withTaskGroup(of: Void.self) { group in
                if config.llmEnabled {
                    group.addTask {
                        await self.runLLM(text: text, config: config, apiKey: apiKey)
                    }
                }
                if config.baiduEnabled {
                    group.addTask {
                        await self.runBaidu(text: text, config: config, secret: baiduKey)
                    }
                }
            }

            guard !Task.isCancelled else { return }
            self.isTranslating = false

            if config.autoCopy, let output = self.results
                .first(where: { !$0.text.isEmpty })?
                .text {
                self.writeToPasteboard(output)
            }
        }
    }

    func copyOutput() {
        copyText(primaryText)
    }

    func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        writeToPasteboard(text)
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTranslating = false
    }

    private func runLLM(text: String, config: AppConfig, apiKey: String) async {
        do {
            _ = try await service.translate(
                text: text,
                config: config,
                apiKey: apiKey
            ) { [weak self] partial in
                self?.update("llm") { result in
                    result.text = partial
                    result.isStreaming = true
                }
            }
            guard !Task.isCancelled else { return }
            update("llm") { $0.isStreaming = false }
        } catch {
            guard !Task.isCancelled else { return }
            update("llm") {
                $0.error = error.localizedDescription
                $0.isStreaming = false
            }
        }
    }

    private func runBaidu(text: String, config: AppConfig, secret: String) async {
        update("baidu") { $0.isStreaming = true }
        do {
            let output = try await service.translateBaidu(
                text: text,
                config: config,
                secret: secret
            )
            guard !Task.isCancelled else { return }
            update("baidu") {
                $0.text = output
                $0.isStreaming = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            update("baidu") {
                $0.error = error.localizedDescription
                $0.isStreaming = false
            }
        }
    }

    private func update(_ id: String, _ change: (inout ProviderResult) -> Void) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        change(&results[index])
    }

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        didCopy = true

        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    private static func llmTitle(_ config: AppConfig) -> String {
        config.model.isEmpty ? "AI 翻译" : "AI 翻译 · \(config.model)"
    }
}


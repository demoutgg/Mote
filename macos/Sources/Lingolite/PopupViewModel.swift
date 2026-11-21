// 悬浮窗状态：串行化翻译请求并丢弃过期结果；不负责持久化配置。
import Combine
import Foundation

final class PopupViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var output = ""
    @Published var isTranslating = false
    @Published var errorMessage: String?

    private let store: SettingsStore
    private let service: TranslationService
    private var task: Task<Void, Never>?

    init(store: SettingsStore, service: TranslationService) {
        self.store = store
        self.service = service
    }

    func translate() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        task?.cancel()
        output = ""
        errorMessage = nil
        isTranslating = true

        let config = store.config
        let apiKey = store.apiKey

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.translate(
                    text: text,
                    config: config,
                    apiKey: apiKey
                ) { [weak self] partial in
                    self?.output = partial
                }
                if !Task.isCancelled {
                    self.isTranslating = false
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isTranslating = false
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTranslating = false
    }
}


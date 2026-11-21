// 设置窗口：分页编辑服务、翻译与通用选项；保存前不写入磁盘。
import AppKit
import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var onStatusIconPreview: (String) -> Void
    var onClose: () -> Void

    @State private var draft: AppConfig
    @State private var draftKey: String
    @State private var draftBaiduKey: String
    @State private var isTesting = false
    @State private var isTestingBaidu = false
    @State private var isFetchingModels = false
    @State private var modelOptions: [String] = []
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var baiduResult: String?
    @State private var baiduSucceeded = false
    @State private var showAdvanced = false

    private let service = TranslationService()

    init(
        store: SettingsStore,
        onStatusIconPreview: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.onStatusIconPreview = onStatusIconPreview
        self.onClose = onClose
        _draft = State(initialValue: store.config)
        _draftKey = State(initialValue: store.apiKey)
        _draftBaiduKey = State(initialValue: store.baiduKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab
                    .tabItem { Label("通用", systemImage: "gearshape") }
                servicesTab
                    .tabItem { Label("服务", systemImage: "square.stack.3d.up") }
                translationTab
                    .tabItem { Label("翻译", systemImage: "character.bubble") }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            HStack(spacing: 10) {
                if !draft.llmEnabled && !draft.baiduEnabled {
                    Label("至少启用一个翻译服务", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if shortcutConflict {
                    Label("存在重复快捷键", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("取消") {
                    onStatusIconPreview(store.config.statusIcon)
                    onClose()
                }
                Button("保存") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(shortcutConflict)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 640, height: 620)
        .onExitCommand {
            onClose()
        }
    }

    private var servicesTab: some View {
        Form {
            Section("AI 翻译（OpenAI 兼容）") {
                Toggle("启用 AI 翻译", isOn: $draft.llmEnabled)

                if draft.llmEnabled {
                    HStack {
                        TextField("接口地址", text: $draft.endpoint, prompt: Text("https://api.openai.com/v1"))
                        Menu(currentPreset?.rawValue ?? "自定义") {
                            ForEach(ServicePreset.allCases, id: \.self) { preset in
                                Button {
                                    draft.endpoint = preset.endpoint
                                    draft.model = preset.model
                                } label: {
                                    if currentPreset == preset {
                                        Label(preset.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(preset.rawValue)
                                    }
                                }
                            }
                        }
                        .fixedSize()
                    }

                    SecureField("API Key", text: $draftKey, prompt: Text("留空则不发送 Authorization，可直接粘贴"))

                    HStack {
                        TextField("模型", text: $draft.model, prompt: Text("gpt-4o-mini"))

                        Button(isFetchingModels ? "获取中…" : "获取模型") {
                            fetchModels()
                        }
                        .disabled(isFetchingModels || draft.endpoint.isEmpty)

                        if !modelOptions.isEmpty {
                            Menu("可选 \(modelOptions.count) 个") {
                                ForEach(modelOptions, id: \.self) { model in
                                    Button {
                                        draft.model = model
                                    } label: {
                                        if draft.model == model {
                                            Label(model, systemImage: "checkmark")
                                        } else {
                                            Text(model)
                                        }
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }

                    HStack(spacing: 10) {
                        Button(isTesting ? "测试中…" : "测试连接") {
                            runTest()
                        }
                        .disabled(isTesting || draft.endpoint.isEmpty || draft.model.isEmpty)

                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let testResult {
                            Text(testResult)
                                .font(.caption)
                                .foregroundStyle(testSucceeded ? Color.green : Color.red)
                                .lineLimit(2)
                        }
                        Spacer()
                    }

                    Text("Key 只保存在本机钥匙串。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("百度翻译") {
                Toggle("启用百度翻译", isOn: $draft.baiduEnabled)

                if draft.baiduEnabled {
                    TextField("AppID", text: $draft.baiduAppID)
                    SecureField("密钥", text: $draftBaiduKey, prompt: Text("百度翻译开放平台的密钥"))

                    HStack(spacing: 10) {
                        Button(isTestingBaidu ? "测试中…" : "测试百度翻译") {
                            runBaiduTest()
                        }
                        .disabled(
                            isTestingBaidu
                                || draft.baiduAppID.isEmpty
                                || draftBaiduKey.isEmpty
                        )

                        if isTestingBaidu {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let baiduResult {
                            Text(baiduResult)
                                .font(.caption)
                                .foregroundStyle(baiduSucceeded ? Color.green : Color.red)
                                .lineLimit(2)
                        }
                        Spacer()
                    }

                    Link("打开百度翻译开放平台", destination: URL(string: "https://fanyi-api.baidu.com/")!)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var translationTab: some View {
        Form {
            Section("语言") {
                Picker("目标语言", selection: $draft.targetLanguage) {
                    ForEach(AppConfig.targetLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }

                Toggle("翻译完成后自动复制译文", isOn: $draft.autoCopy)
            }

            Section("AI 参数") {
                HStack {
                    Text("随机性")
                    Slider(value: $draft.temperature, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", draft.temperature))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("系统提示词", isExpanded: $showAdvanced) {
                    TextEditor(text: $draft.systemPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 220)
                        .padding(4)
                        .scrollContentBackground(.hidden)
                        .background(
                            Color(nsColor: .textBackgroundColor).opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )

                    HStack {
                        Text("使用 {targetLang} 表示目标语言。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") {
                            draft.systemPrompt = AppConfig.defaultPrompt
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("快捷键") {
                ForEach(ShortcutAction.allCases) { action in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        ShortcutRecorder(binding: draft.binding(for: action)) { binding in
                            draft.setBinding(binding, for: action)
                        }
                        .frame(width: 96, height: 24)

                        Button {
                            draft.resetBinding(for: action)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("恢复默认")
                    }
                }

                Text("选中翻译需要辅助功能权限；截图功能需要屏幕录制权限。若快捷键被 Bob、MoePeek 等应用占用，需要先关闭对方的同名快捷键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("弹窗") {
                HStack {
                    Text("宽度")
                    Slider(value: $draft.popupWidth, in: 460...900, step: 10)
                    Text("\(Int(draft.popupWidth)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                HStack {
                    Text("高度")
                    Slider(value: $draft.popupHeight, in: 340...800, step: 10)
                    Text("\(Int(draft.popupHeight)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                Text("也可以在弹窗右下角拖动调整，位置会自动记住。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("外观") {
                HStack(spacing: 10) {
                    Text("菜单栏图标")
                    Spacer()
                    statusIconPreview
                    Menu("内置图标") {
                        ForEach(AppConfig.statusIcons, id: \.self) { icon in
                            Button {
                                draft.statusIcon = icon
                                onStatusIconPreview(icon)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: icon)
                                        .frame(width: 16)
                                    Text(statusIconName(icon))
                                    if draft.statusIcon == icon {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("显示“译”字") {
                            draft.statusIcon = ""
                            onStatusIconPreview("")
                        }
                    }
                    .fixedSize()
                }

                TextField(
                    "自定义 SF Symbol 名称",
                    text: $draft.statusIcon,
                    prompt: Text("character.bubble.fill")
                )
                .onChange(of: draft.statusIcon) { value in
                    onStatusIconPreview(value)
                }

                Text("留空显示“译”字；支持任意 SF Symbols 名称。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                HStack {
                    Text("Lingolite")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
                        .foregroundStyle(.secondary)
                }
                Link("github.com/demoutgg/lingolite", destination: URL(string: "https://github.com/demoutgg/lingolite")!)
                    .font(.caption)
                Text("翻译在本地发起，不经过 Lingolite 服务器；不收集遥测。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        store.config = draft
        store.apiKey = draftKey
        store.baiduKey = draftBaiduKey
        store.save()
        onStatusIconPreview(draft.statusIcon)
        onClose()
    }

    private var currentPreset: ServicePreset? {
        ServicePreset.detect(draft.endpoint)
    }

    private var shortcutConflict: Bool {
        let signatures = ShortcutAction.allCases.map { action -> String in
            let binding = draft.binding(for: action)
            return "\(binding.keyCode)-\(binding.modifiers)"
        }
        return Set(signatures).count != signatures.count
    }

    private func runTest() {
        isTesting = true
        testResult = nil

        let config = draft
        let apiKey = draftKey
        Task { @MainActor in
            defer { isTesting = false }
            let start = Date()
            do {
                let output = try await service.translate(
                    text: "Hello",
                    config: config,
                    apiKey: apiKey
                ) { _ in }
                testSucceeded = true
                let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
                testResult = "连接成功 · \(config.model) · \(milliseconds) ms · \(output.prefix(20))"
            } catch {
                testSucceeded = false
                testResult = error.localizedDescription
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        testResult = nil

        let config = draft
        let apiKey = draftKey
        Task { @MainActor in
            defer { isFetchingModels = false }
            do {
                var models = try await service.fetchModels(config: config, apiKey: apiKey)
                if !draft.model.isEmpty && !models.contains(draft.model) {
                    models.insert(draft.model, at: 0)
                }
                modelOptions = models
                testSucceeded = true
                testResult = "已获取 \(models.count) 个模型"
            } catch {
                testSucceeded = false
                testResult = error.localizedDescription
            }
        }
    }

    private func runBaiduTest() {
        isTestingBaidu = true
        baiduResult = nil

        let config = draft
        let secret = draftBaiduKey
        Task { @MainActor in
            defer { isTestingBaidu = false }
            let start = Date()
            do {
                let output = try await service.translateBaidu(
                    text: "Hello",
                    config: config,
                    secret: secret
                )
                baiduSucceeded = true
                let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
                baiduResult = "连接成功 · \(milliseconds) ms · \(output.prefix(20))"
            } catch {
                baiduSucceeded = false
                baiduResult = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var statusIconPreview: some View {
        if !draft.statusIcon.isEmpty,
           NSImage(systemSymbolName: draft.statusIcon, accessibilityDescription: nil) != nil {
            Image(systemName: draft.statusIcon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            Text("译")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func statusIconName(_ icon: String) -> String {
        switch icon {
        case "sparkles":
            return "星光（双星）"
        case "sparkle":
            return "星光（单星）"
        default:
            return icon
        }
    }

    private enum ServicePreset: String, CaseIterable {
        case openAI = "OpenAI"
        case deepSeek = "DeepSeek"
        case ollama = "Ollama（本地）"
        case lmStudio = "LM Studio（本地）"

        var endpoint: String {
            switch self {
            case .openAI:
                return "https://api.openai.com/v1"
            case .deepSeek:
                return "https://api.deepseek.com/v1"
            case .ollama:
                return "http://127.0.0.1:11434/v1"
            case .lmStudio:
                return "http://127.0.0.1:1234/v1"
            }
        }

        var model: String {
            switch self {
            case .openAI:
                return "gpt-4o-mini"
            case .deepSeek:
                return "deepseek-chat"
            case .ollama:
                return "qwen2.5:7b"
            case .lmStudio:
                return "local-model"
            }
        }

        static func detect(_ endpoint: String) -> ServicePreset? {
            let lower = endpoint.lowercased()
            if lower.contains("api.openai.com") {
                return .openAI
            }
            if lower.contains("api.deepseek.com") {
                return .deepSeek
            }
            if lower.contains("11434") {
                return .ollama
            }
            if lower.contains("1234") {
                return .lmStudio
            }
            return nil
        }
    }
}

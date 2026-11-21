// 设置窗口：编辑草稿、快速填充服务商、测试连通性；保存前不写入磁盘。
import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var onClose: () -> Void

    @State private var draft: AppConfig
    @State private var draftKey: String
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    private let service = TranslationService()

    init(store: SettingsStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _draft = State(initialValue: store.config)
        _draftKey = State(initialValue: store.apiKey)
    }

    var body: some View {
        Form {
            Section("API") {
                HStack {
                    TextField("Endpoint", text: $draft.endpoint)
                    Menu("快速填充") {
                        Button("OpenAI") {
                            draft.endpoint = "https://api.openai.com/v1"
                            draft.model = "gpt-4o-mini"
                        }
                        Button("DeepSeek") {
                            draft.endpoint = "https://api.deepseek.com/v1"
                            draft.model = "deepseek-chat"
                        }
                        Button("Ollama（本地）") {
                            draft.endpoint = "http://127.0.0.1:11434/v1"
                            draft.model = "qwen2.5:7b"
                        }
                        Button("LM Studio（本地）") {
                            draft.endpoint = "http://127.0.0.1:1234/v1"
                            draft.model = "local-model"
                        }
                    }
                    .fixedSize()
                }

                SecureField("API Key", text: $draftKey)
                TextField("Model", text: $draft.model)

                HStack(spacing: 10) {
                    Button(isTesting ? "Testing…" : "Test") {
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
                            .lineLimit(3)
                    }
                    Spacer()
                }
            }

            Section("Translation") {
                TextField("Target language", text: $draft.targetLanguage)

                Text("System prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.systemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 170)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )

                HStack {
                    Text("Temperature")
                    Slider(value: $draft.temperature, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", draft.temperature))
                        .monospacedDigit()
                }
            }

            Section {
                Text("API Key 保存在 macOS 钥匙串；其余配置写入 ~/Library/Application Support/Lingolite/config.json。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("全局快捷键：⌥L。Esc 关闭悬浮窗。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onClose()
                }
                Button("Save") {
                    store.config = draft
                    store.apiKey = draftKey
                    store.save()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 600, height: 640)
        .onExitCommand {
            onClose()
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil

        let config = draft
        let apiKey = draftKey
        Task { @MainActor in
            defer { isTesting = false }
            do {
                let output = try await service.translate(
                    text: "Hello",
                    config: config,
                    apiKey: apiKey
                ) { _ in }
                testSucceeded = true
                testResult = "连接成功：\(output.prefix(40))"
            } catch {
                testSucceeded = false
                testResult = error.localizedDescription
            }
        }
    }
}


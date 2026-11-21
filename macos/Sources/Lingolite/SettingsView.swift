import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var onClose: () -> Void

    var body: some View {
        Form {
            Section("API") {
                TextField("Endpoint", text: $store.config.endpoint)
                SecureField("API Key", text: $store.apiKey)
                TextField("Model", text: $store.config.model)
            }

            Section("Translation") {
                TextField("Target language", text: $store.config.targetLanguage)

                Text("System prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $store.config.systemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 170)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )

                HStack {
                    Text("Temperature")
                    Slider(value: $store.config.temperature, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", store.config.temperature))
                        .monospacedDigit()
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onClose()
                }
                Button("Save") {
                    store.save()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 580, height: 560)
    }
}


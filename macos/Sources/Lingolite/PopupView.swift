import AppKit
import SwiftUI

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    @ObservedObject var store: SettingsStore
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lingolite")
                    .font(.headline)
                Spacer()
                Text(store.config.targetLanguage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $model.sourceText)
                .font(.system(size: 13))
                .frame(height: 64)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )

            HStack(spacing: 8) {
                if model.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.isTranslating ? "Translating…" : store.config.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Translate") {
                    model.translate()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }

            ScrollView {
                Text(model.output.isEmpty ? "Select text and press ⌥L, or type above." : model.output)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.output, forType: .string)
                }
                .disabled(model.output.isEmpty)
                Spacer()
                Button("Close") {
                    onClose()
                }
            }
        }
        .padding(14)
        .frame(width: 480, height: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary)
        )
    }
}


// 悬浮翻译窗：中文界面、原文/译文分层、快捷键与权限引导；不处理选区读取和网络。
import AppKit
import SwiftUI

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    @ObservedObject var store: SettingsStore
    var onClose: () -> Void
    var onOpenSettings: () -> Void
    var onResize: (CGSize) -> Void
    var onResizeEnd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 8) {
                sourceHeader
                sourceEditor
                actionRow

                if let error = model.errorMessage {
                    errorBanner(error)
                }

                resultHeader
                    .padding(.top, 2)
                resultSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09))
        )
        .overlay(alignment: .bottomTrailing) {
            resizeGrip
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Text("Lingolite")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            languageMenu

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开设置")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭（Esc）")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppConfig.targetLanguages, id: \.self) { language in
                Button {
                    store.config.targetLanguage = language
                    store.save()
                } label: {
                    if store.config.targetLanguage == language {
                        Label(language, systemImage: "checkmark")
                    } else {
                        Text(language)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.config.targetLanguageLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("目标语言")
    }

    private var sourceEditor: some View {
        TranslatingTextEditor(
            text: $model.sourceText,
            placeholder: "输入要翻译的文本，或按 ⌥D 框选屏幕区域",
            focusToken: model.focusToken,
            onSubmit: { model.translate() }
        )
        .frame(height: 84)
        .padding(6)
        .background(
            Color(nsColor: .textBackgroundColor).opacity(0.55),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }

    private var sourceHeader: some View {
        HStack {
            Text("原文")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if !model.sourceText.isEmpty {
                Button("清空") {
                    model.clear()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var resultHeader: some View {
        HStack(spacing: 6) {
            Text("译文")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if !model.results.isEmpty {
                Text("\(model.results.count) 个服务")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                model.copyOutput()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                    Text(model.didCopy ? "已复制" : "复制")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.primaryText.isEmpty ? Color.secondary.opacity(0.4) : Color.secondary)
            .disabled(model.primaryText.isEmpty)
            .help("复制译文")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if model.isTranslating {
                ProgressView()
                    .controlSize(.small)
                Text("翻译中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(store.config.model)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("\(model.sourceText.count) 字符")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Text("⌘↩ 翻译")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)

            Button {
                model.translate()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("翻译")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isTranslating || model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("翻译（⌘↩）")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Button("重试") {
                    model.translate()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))

                Button("设置") {
                    onOpenSettings()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var resultSection: some View {
        ScrollView {
            if model.results.isEmpty {
                emptyResult
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.results) { result in
                        resultCard(result)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func resultCard(_ result: ProviderResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(result.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if result.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                }

                Spacer()

                if !result.text.isEmpty {
                    Button {
                        model.copyText(result.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("复制这条译文")
                }
            }

            if let error = result.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if result.text.isEmpty {
                Text(result.isStreaming ? "正在翻译…" : "等待结果…")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                Text(result.text)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var emptyResult: some View {
        VStack(spacing: 8) {
            if model.isTranslating {
                ProgressView()
                    .controlSize(.small)
                Text("正在翻译…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "text.bubble")
                    .font(.system(size: 24))
                    .foregroundStyle(.quaternary)
                Text("翻译结果会显示在这里")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("选中文本按 ⌥D，或输入后按 ⌘↩")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onResize(value.translation)
                    }
                    .onEnded { _ in
                        onResizeEnd()
                    }
            )
            .help("拖动调整窗口大小")
    }
}


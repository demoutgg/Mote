// 纯 AppKit 翻译弹窗：避免常驻 SwiftUI 框架和视图图。
import AppKit
import Combine

final class PopupContentView: NSView, NSTextViewDelegate {
    private let model: PopupViewModel
    private let store: SettingsStore
    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void

    private let background = NSView()
    private let iconView = NSImageView()
    private let languageButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let historyButton = NSButton()
    private let settingsButton = NSButton()
    private let closeButton = NSButton()

    private let sourceLabel = NSTextField(labelWithString: "原文")
    private let clearButton = NSButton()
    private let sourceScroll = NSScrollView()
    private let sourceTextView = PlaceholderTextView()

    private let translateButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    private let resultLabel = NSTextField(labelWithString: "译文")
    private let copyButton = NSButton()
    private let resultScroll = NSScrollView()
    private let resultTextView = NSTextView()

    private var cancellables = Set<AnyCancellable>()

    override var isFlipped: Bool { true }

    init(
        model: PopupViewModel,
        store: SettingsStore,
        onClose: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void
    ) {
        self.model = model
        self.store = store
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        super.init(frame: .zero)
        setup()
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focusEditor() {
        window?.makeFirstResponder(sourceTextView)
    }

    private func setup() {
        wantsLayer = true

        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        background.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        addSubview(background)

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        let languageItems = ["自动"] + AppConfig.targetLanguages.filter {
            $0 != AppConfig.autoTargetLanguage
        }
        languageButton.addItems(withTitles: languageItems)
        languageButton.selectItem(
            withTitle: store.config.targetLanguage == AppConfig.autoTargetLanguage
                ? "自动"
                : store.config.targetLanguage
        )
        languageButton.controlSize = .small
        languageButton.font = .systemFont(ofSize: 11)
        languageButton.target = self
        languageButton.action = #selector(languageChanged)
        languageButton.toolTip = "目标语言"
        addSubview(languageButton)

        configureIconButton(historyButton, symbol: "clock.arrow.circlepath", action: #selector(openHistory))
        historyButton.toolTip = "历史记录"
        addSubview(historyButton)

        configureIconButton(settingsButton, symbol: "gearshape", action: #selector(openSettings))
        settingsButton.toolTip = "打开设置"
        addSubview(settingsButton)

        configureIconButton(closeButton, symbol: "xmark", action: #selector(closePopup))
        closeButton.toolTip = "关闭（Esc）"
        addSubview(closeButton)

        sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sourceLabel.textColor = .secondaryLabelColor
        addSubview(sourceLabel)

        clearButton.title = "清空"
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 10)
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearSource)
        addSubview(clearButton)

        configureSourceEditor()
        addSubview(sourceScroll)

        translateButton.title = "翻译"
        translateButton.bezelStyle = .rounded
        translateButton.controlSize = .small
        translateButton.font = .systemFont(ofSize: 12, weight: .medium)
        translateButton.target = self
        translateButton.action = #selector(translate)
        addSubview(translateButton)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        addSubview(statusLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        addSubview(spinner)

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemOrange
        errorLabel.maximumNumberOfLines = 3
        errorLabel.isHidden = true
        addSubview(errorLabel)

        resultLabel.font = .systemFont(ofSize: 11, weight: .medium)
        resultLabel.textColor = .secondaryLabelColor
        addSubview(resultLabel)

        copyButton.title = "复制"
        copyButton.isBordered = false
        copyButton.font = .systemFont(ofSize: 10)
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyResult)
        addSubview(copyButton)

        configureResultView()
        addSubview(resultScroll)

        updateStatus()
        updateResults()
        updateTranslating()
        updateError()
        updateCopyTitle()
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
    }

    private func configureSourceEditor() {
        sourceScroll.drawsBackground = false
        sourceScroll.hasVerticalScroller = true
        sourceScroll.autohidesScrollers = true
        sourceScroll.borderType = .noBorder
        sourceScroll.wantsLayer = true
        sourceScroll.layer?.cornerRadius = 10
        sourceScroll.layer?.masksToBounds = true
        sourceScroll.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        sourceScroll.layer?.borderWidth = 1
        sourceScroll.layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(0.35)
            .cgColor

        sourceTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 88)
        sourceTextView.minSize = NSSize(width: 0, height: 0)
        sourceTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        sourceTextView.isVerticallyResizable = true
        sourceTextView.isHorizontallyResizable = false
        sourceTextView.autoresizingMask = [.width]
        sourceTextView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        sourceTextView.textContainer?.widthTracksTextView = true
        sourceTextView.isRichText = false
        sourceTextView.importsGraphics = false
        sourceTextView.font = .systemFont(ofSize: 13)
        sourceTextView.textColor = .labelColor
        sourceTextView.drawsBackground = false
        sourceTextView.textContainerInset = NSSize(width: 6, height: 8)
        sourceTextView.isAutomaticQuoteSubstitutionEnabled = false
        sourceTextView.isAutomaticDashSubstitutionEnabled = false
        sourceTextView.isAutomaticTextReplacementEnabled = false
        sourceTextView.allowsUndo = true
        sourceTextView.placeholder = "输入要翻译的文本，或按 ⌥D 框选屏幕区域"
        sourceTextView.delegate = self
        sourceScroll.documentView = sourceTextView
    }

    private func configureResultView() {
        resultScroll.drawsBackground = false
        resultScroll.hasVerticalScroller = true
        resultScroll.autohidesScrollers = true
        resultScroll.borderType = .noBorder
        resultScroll.wantsLayer = true
        resultScroll.layer?.cornerRadius = 9
        resultScroll.layer?.masksToBounds = true
        resultScroll.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        resultScroll.layer?.borderWidth = 1
        resultScroll.layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(0.35)
            .cgColor

        resultTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        resultTextView.minSize = NSSize(width: 0, height: 0)
        resultTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        resultTextView.isVerticallyResizable = true
        resultTextView.isHorizontallyResizable = false
        resultTextView.autoresizingMask = [.width]
        resultTextView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        resultTextView.textContainer?.widthTracksTextView = true
        resultTextView.isEditable = false
        resultTextView.isSelectable = true
        resultTextView.isRichText = true
        resultTextView.drawsBackground = false
        resultTextView.textContainerInset = NSSize(width: 8, height: 8)
        resultScroll.documentView = resultTextView
    }

    private func bind() {
        model.$sourceText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                if self.sourceTextView.string != text {
                    self.sourceTextView.string = text
                }
                self.updateStatus()
            }
            .store(in: &cancellables)

        model.$results
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateResults()
            }
            .store(in: &cancellables)

        model.$isTranslating
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTranslating()
            }
            .store(in: &cancellables)

        model.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateError()
            }
            .store(in: &cancellables)

        model.$didCopy
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateCopyTitle()
            }
            .store(in: &cancellables)

        model.$focusToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.focusEditor()
                }
            }
            .store(in: &cancellables)

        store.$config
            .map(\.targetLanguage)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] language in
                let display = language == AppConfig.autoTargetLanguage ? "自动" : language
                self?.languageButton.selectItem(withTitle: display)
            }
            .store(in: &cancellables)
    }

    override func layout() {
        super.layout()

        background.frame = bounds

        let padding: CGFloat = 16
        let width = bounds.width
        let height = bounds.height
        let buttonSize: CGFloat = 24

        iconView.frame = NSRect(x: padding, y: 10, width: 26, height: 26)
        closeButton.frame = NSRect(
            x: width - padding - buttonSize,
            y: 11,
            width: buttonSize,
            height: buttonSize
        )
        settingsButton.frame = NSRect(
            x: closeButton.frame.minX - 4 - buttonSize,
            y: 11,
            width: buttonSize,
            height: buttonSize
        )
        historyButton.frame = NSRect(
            x: settingsButton.frame.minX - 4 - buttonSize,
            y: 11,
            width: buttonSize,
            height: buttonSize
        )
        languageButton.frame = NSRect(
            x: historyButton.frame.minX - 8 - 120,
            y: 10,
            width: 120,
            height: 24
        )

        sourceLabel.frame = NSRect(x: padding, y: 50, width: 80, height: 18)
        clearButton.frame = NSRect(
            x: width - padding - 44,
            y: 49,
            width: 44,
            height: 18
        )
        sourceScroll.frame = NSRect(
            x: padding,
            y: 72,
            width: width - padding * 2,
            height: 88
        )

        translateButton.frame = NSRect(
            x: width - padding - 80,
            y: 166,
            width: 80,
            height: 28
        )
        statusLabel.frame = NSRect(x: padding, y: 172, width: 200, height: 18)
        spinner.frame = NSRect(
            x: statusLabel.frame.maxX + 6,
            y: 173,
            width: 16,
            height: 16
        )

        let errorVisible = !errorLabel.isHidden
        if errorVisible {
            errorLabel.frame = NSRect(
                x: padding,
                y: 200,
                width: width - padding * 2,
                height: 34
            )
        }

        let resultLabelY: CGFloat = errorVisible ? 240 : 202
        resultLabel.frame = NSRect(x: padding, y: resultLabelY, width: 80, height: 18)
        copyButton.frame = NSRect(
            x: width - padding - 54,
            y: resultLabelY - 1,
            width: 54,
            height: 18
        )

        let resultTop = resultLabelY + 22
        resultScroll.frame = NSRect(
            x: padding,
            y: resultTop,
            width: width - padding * 2,
            height: max(height - resultTop - 14, 80)
        )
    }

    private func updateStatus() {
        if model.isTranslating {
            statusLabel.stringValue = "翻译中…"
        } else {
            statusLabel.stringValue = "\(model.sourceText.count) 字符"
        }
        translateButton.isEnabled =
            !model.isTranslating
            && !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func updateResults() {
        if model.results.isEmpty {
            let text = model.isTranslating ? "翻译中…" : "翻译结果会显示在这里"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            resultTextView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: attributes)
            )
            copyButton.isEnabled = false
            return
        }

        let output = NSMutableAttributedString()
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for (index, result) in model.results.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }
            output.append(NSAttributedString(
                string: result.title + "\n",
                attributes: titleAttributes
            ))

            let body: String
            let color: NSColor
            if let error = result.error {
                body = error
                color = .systemOrange
            } else if result.text.isEmpty {
                body = result.isStreaming ? "正在翻译…" : "等待结果…"
                color = .tertiaryLabelColor
            } else {
                body = result.text
                color = .labelColor
            }
            output.append(NSAttributedString(
                string: body,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: color,
                ]
            ))
        }

        resultTextView.textStorage?.setAttributedString(output)
        resultTextView.scrollToBeginningOfDocument(nil)
        copyButton.isEnabled = !model.primaryText.isEmpty
    }

    private func updateTranslating() {
        if model.isTranslating {
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
        updateStatus()
        updateResults()
    }

    private func updateError() {
        let message = model.errorMessage ?? ""
        errorLabel.stringValue = message
        errorLabel.isHidden = message.isEmpty
        needsLayout = true
    }

    private func updateCopyTitle() {
        copyButton.title = model.didCopy ? "已复制" : "复制"
    }

    @objc private func translate() {
        model.translate()
    }

    @objc private func clearSource() {
        model.clear()
        focusEditor()
    }

    @objc private func copyResult() {
        model.copyOutput()
    }

    @objc private func languageChanged() {
        let title = languageButton.titleOfSelectedItem ?? "简体中文"
        store.config.targetLanguage =
            title == "自动" ? AppConfig.autoTargetLanguage : title
        store.save()
    }

    @objc private func closePopup() {
        onClose()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openHistory() {
        onOpenHistory()
    }

    func textDidChange(_ notification: Notification) {
        model.sourceText = sourceTextView.string
        updateStatus()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let flags = NSApp.currentEvent?
                .modifierFlags
                .intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.command) || flags.contains(.option) || flags.contains(.shift) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            }
            model.translate()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onClose()
            return true
        }
        return false
    }
}

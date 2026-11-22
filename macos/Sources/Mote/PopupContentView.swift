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
    private let sourceCard = NSView()
    private let sourceScroll = NSScrollView()
    private let sourceTextView = PlaceholderTextView()

    private let translateButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let errorLabel = NSTextField(labelWithString: "")

    private let resultLabel = NSTextField(labelWithString: "译文")
    private let copyButton = NSButton()
    private let resultCard = NSView()
    private let resultScroll = NSScrollView()
    private let resultTextView = NSTextView()

    private var badges: [BadgeView] = []
    private var resultRanges: [String: NSRange] = [:]
    private var copyMenuShown = false
    private var didScrollForRun = false
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
        addSubview(background)

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
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
        configureCard(sourceCard)
        sourceCard.addSubview(sourceScroll)
        addSubview(sourceCard)

        translateButton.title = "翻译"
        translateButton.bezelStyle = .rounded
        translateButton.controlSize = .small
        translateButton.font = .systemFont(ofSize: 12, weight: .medium)
        // 输入框里按 ↩ 就是翻译，按钮做成主操作用的强调色，快捷键放 tooltip
        translateButton.bezelColor = .controlAccentColor
        translateButton.contentTintColor = .white
        translateButton.toolTip = "翻译（↩）"
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
        errorLabel.lineBreakMode = .byTruncatingTail
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
        configureCard(resultCard)
        resultCard.addSubview(resultScroll)
        addSubview(resultCard)

        updateStatus()
        updateResults()
        updateTranslating()
        updateError()
        updateCopyTitle()
    }

    private func configureCard(_ card: NSView) {
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
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
        sourceTextView.textContainerInset = NSSize(width: 10, height: 10)
        sourceTextView.isAutomaticQuoteSubstitutionEnabled = false
        sourceTextView.isAutomaticDashSubstitutionEnabled = false
        sourceTextView.isAutomaticTextReplacementEnabled = false
        sourceTextView.allowsUndo = true
        sourceTextView.placeholder = "输入要翻译的文本"
        sourceTextView.delegate = self
        sourceScroll.documentView = sourceTextView
    }

    private func configureResultView() {
        resultScroll.drawsBackground = false
        resultScroll.hasVerticalScroller = true
        resultScroll.autohidesScrollers = true
        resultScroll.borderType = .noBorder

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
        resultTextView.textContainerInset = NSSize(width: 10, height: 10)
        resultScroll.documentView = resultTextView
    }

    /// 宽度不同步时文本要么提前换行、要么横向溢出被裁，两者都不对
    private func syncEditorWidth(_ textView: NSTextView, to width: CGFloat) {
        guard width > 1, abs(textView.frame.width - width) > 0.5 else { return }
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
    }

    private func bind() {
        model.$sourceText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                if self.sourceTextView.string != text {
                    self.sourceTextView.string = text
                    // 长文本默认滚到尾部，这里回到开头，避免首行被切掉
                    let start = NSRange(location: 0, length: 0)
                    self.sourceTextView.setSelectedRange(start)
                    self.sourceTextView.scrollRangeToVisible(start)
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

        model.$runID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.didScrollForRun = false
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
        let topHeight: CGFloat = 44

        iconView.frame = NSRect(x: padding, y: (topHeight - 22) / 2, width: 22, height: 22)
        closeButton.frame = NSRect(
            x: width - padding - buttonSize,
            y: (topHeight - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )
        settingsButton.frame = NSRect(
            x: closeButton.frame.minX - 2 - buttonSize,
            y: closeButton.frame.minY,
            width: buttonSize,
            height: buttonSize
        )
        historyButton.frame = NSRect(
            x: settingsButton.frame.minX - 2 - buttonSize,
            y: closeButton.frame.minY,
            width: buttonSize,
            height: buttonSize
        )
        languageButton.frame = NSRect(
            x: historyButton.frame.minX - 10 - 120,
            y: (topHeight - 24) / 2,
            width: 120,
            height: 24
        )

        let headerY = topHeight + 12
        sourceLabel.frame = NSRect(x: padding, y: headerY, width: 80, height: 16)
        clearButton.frame = NSRect(
            x: width - padding - 44,
            y: headerY - 1,
            width: 44,
            height: 18
        )
        sourceCard.frame = NSRect(
            x: padding,
            y: headerY + 22,
            width: width - padding * 2,
            height: 96
        )
        sourceScroll.frame = sourceCard.bounds
        // NSTextView 宽度不会自动跟随滚动区：偏窄会提前换行，偏宽则横向溢出被裁
        syncEditorWidth(sourceTextView, to: sourceCard.bounds.width)

        let toolY = sourceCard.frame.maxY + 10
        translateButton.frame = NSRect(
            x: width - padding - 72,
            y: toolY,
            width: 72,
            height: 26
        )
        let statusWidth = max(translateButton.frame.minX - padding - 12, 60)
        let statusY = toolY + 5
        if spinner.isHidden {
            statusLabel.frame = NSRect(x: padding, y: statusY, width: statusWidth, height: 16)
        } else {
            spinner.frame = NSRect(x: padding, y: statusY + 1, width: 14, height: 14)
            statusLabel.frame = NSRect(
                x: padding + 20,
                y: statusY,
                width: statusWidth - 20,
                height: 16
            )
        }
        errorLabel.frame = NSRect(x: padding, y: statusY, width: statusWidth, height: 16)

        let resultHeaderY = toolY + 26 + 12
        resultLabel.frame = NSRect(x: padding, y: resultHeaderY, width: 40, height: 16)
        let copyWidth: CGFloat = copyMenuShown ? 66 : 44
        copyButton.frame = NSRect(
            x: width - padding - copyWidth,
            y: resultHeaderY - 1,
            width: copyWidth,
            height: 18
        )

        var badgeX = resultLabel.frame.maxX + 6
        let badgeLimit = copyButton.frame.minX - 8
        for badge in badges {
            let badgeWidth = min(badge.preferredWidth, badgeLimit - badgeX)
            badge.isHidden = badgeWidth < 24
            badge.frame = NSRect(
                x: badgeX,
                y: resultHeaderY + 2,
                width: max(badgeWidth, 0),
                height: 16
            )
            badgeX += badgeWidth + 4
        }

        let resultTop = resultHeaderY + 22
        resultCard.frame = NSRect(
            x: padding,
            y: resultTop,
            width: width - padding * 2,
            height: max(height - resultTop - padding, 60)
        )
        resultScroll.frame = resultCard.bounds
        // 富文本赋值后 NSTextView 会横向撑开，同样收回卡片宽度
        syncEditorWidth(resultTextView, to: resultCard.bounds.width)
        let clipOrigin = resultScroll.contentView.bounds.origin
        if clipOrigin.x != 0 {
            resultScroll.contentView.scroll(to: NSPoint(x: 0, y: clipOrigin.y))
            resultScroll.reflectScrolledClipView(resultScroll.contentView)
        }
    }

    private func updateStatus() {
        if model.isTranslating {
            statusLabel.stringValue = "翻译中…"
        } else {
            statusLabel.stringValue = "\(model.sourceText.count) 字符"
        }
        statusLabel.isHidden = !errorLabel.isHidden
        translateButton.isEnabled =
            !model.isTranslating
            && !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func updateResults() {
        rebuildBadges()
        updateCopyMenuAffordance()

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
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let showTitles = model.results.count > 1
        var ranges: [String: NSRange] = [:]
        for (index, result) in model.results.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }
            let start = output.length
            if showTitles {
                output.append(NSAttributedString(
                    string: result.title + "\n",
                    attributes: titleAttributes
                ))
            }

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
                    .paragraphStyle: paragraph,
                ]
            ))
            ranges[result.id] = NSRange(location: start, length: output.length - start)
        }

        resultTextView.textStorage?.setAttributedString(output)
        resultRanges = ranges
        // 只在每轮翻译开始时回到顶部，流式更新期间保留用户滚动位置。
        if !didScrollForRun {
            resultTextView.scrollToBeginningOfDocument(nil)
            didScrollForRun = true
        }
        copyButton.isEnabled = !model.primaryText.isEmpty
        needsLayout = true
    }

    /// 多服务时复制按钮带下拉箭头，点开可选全部或单个服务。
    private func updateCopyMenuAffordance() {
        let multiple = model.results.count > 1
        let symbol = multiple
            ? NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
                )
            : nil
        copyButton.image = symbol
        copyButton.imagePosition = .imageRight
        copyButton.toolTip = multiple ? "复制全部或指定服务的结果" : "复制译文"

        guard multiple != copyMenuShown else { return }
        copyMenuShown = multiple
        needsLayout = true
    }

    private func rebuildBadges() {
        let titles = model.results.map(\.title)
        if badges.count == titles.count,
           zip(badges, titles).allSatisfy({ pair in pair.0.text == pair.1 }) {
            return
        }

        badges.forEach { $0.removeFromSuperview() }
        badges = model.results.map { result in
            let badge = BadgeView(text: result.title) { [weak self] in
                guard let self, let range = self.resultRanges[result.id] else { return }
                self.resultTextView.scrollRangeToVisible(range)
            }
            addSubview(badge)
            return badge
        }
        needsLayout = true
    }

    private func updateTranslating() {
        if model.isTranslating {
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
        needsLayout = true
        updateStatus()
        updateResults()
    }

    private func updateError() {
        let message = model.errorMessage ?? ""
        errorLabel.stringValue = message
        errorLabel.toolTip = message.isEmpty ? nil : message
        errorLabel.isHidden = message.isEmpty
        updateStatus()
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
        guard model.results.count > 1 else {
            model.copyOutput()
            return
        }

        let menu = NSMenu()
        let all = NSMenuItem(title: "全部复制", action: #selector(copyAll), keyEquivalent: "")
        all.target = self
        menu.addItem(all)
        menu.addItem(.separator())
        for result in model.results {
            let item = NSMenuItem(
                title: result.title,
                action: #selector(copyService(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = result.id
            item.isEnabled = !result.text.isEmpty
            menu.addItem(item)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: copyButton.bounds.height + 4),
            in: copyButton
        )
    }

    @objc private func copyAll() {
        let text = model.results
            .filter { !$0.text.isEmpty }
            .map { "\($0.title)\n\($0.text)" }
            .joined(separator: "\n\n")
        model.copyText(text)
    }

    @objc private func copyService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let result = model.results.first(where: { $0.id == id }) else { return }
        model.copyText(result.text)
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

/// 译文服务徽标：小号胶囊，点击跳到对应服务的结果。
private final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let onClick: () -> Void
    private var naturalSize = NSSize.zero

    var text: String { label.stringValue }

    init(text: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.secondaryLabelColor
            .withAlphaComponent(0.12)
            .cgColor
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = text
        label.sizeToFit()
        naturalSize = label.frame.size
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var preferredWidth: CGFloat {
        ceil(naturalSize.width) + 14
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(
            x: 7,
            y: (bounds.height - naturalSize.height) / 2,
            width: min(naturalSize.width, max(bounds.width - 14, 0)),
            height: naturalSize.height
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit.isDescendant(of: self) ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}

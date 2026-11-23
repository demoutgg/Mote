// 纯 AppKit 翻译弹窗：避免常驻 SwiftUI 框架和视图图。
import AppKit
import Combine

final class PopupContentView: NSView, NSTextViewDelegate {
    private let model: PopupViewModel
    private let store: SettingsStore
    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void

    private let background = FillView()
    private let iconView = NSImageView()
    private let languageButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let historyButton = NSButton()
    private let settingsButton = NSButton()
    private let closeButton = NSButton()

    private let sourceLabel = NSTextField(labelWithString: "原文")
    private let clearButton = NSButton()
    private let sourceCard = FillView()
    private let sourceScroll = NSScrollView()
    private let sourceTextView = PlaceholderTextView()

    private let translateButton = PrimaryButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let errorLabel = NSTextField(labelWithString: "")

    private let resultLabel = NSTextField(labelWithString: "译文")
    private let copyButton = NSButton()
    private let resultCard = FillView()
    private let resultScroll = NSScrollView()
    private let resultTextView = NSTextView()

    private var copyMenuShown = false
    private var didScrollForRun = false
    private var dividerAttachments: [(NSTextAttachment, Int)] = []
    private var dividerBuiltWidth: CGFloat = 0
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

        background.fill = .windowBackgroundColor
        background.cornerRadius = Theme.Radius.popup
        addSubview(background)

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = Theme.Radius.small
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
        languageButton.font = Theme.Font.footnote
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

        sourceLabel.font = Theme.Font.footnote
        sourceLabel.textColor = .secondaryLabelColor
        addSubview(sourceLabel)

        clearButton.title = "清空"
        clearButton.isBordered = false
        clearButton.font = Theme.Font.caption
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearSource)
        addSubview(clearButton)

        configureSourceEditor()
        configureCard(sourceCard)
        sourceCard.addSubview(sourceScroll)
        addSubview(sourceCard)

        translateButton.title = "翻译"
        // 白色符号直接画进自绘按钮，模板图在自绘里没法染色
        translateButton.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
        )
        // 输入框里按 ↩ 就是翻译，按钮做成主操作，快捷键放 tooltip
        translateButton.toolTip = "翻译（↩）"
        translateButton.target = self
        translateButton.action = #selector(translate)
        addSubview(translateButton)

        statusLabel.font = Theme.Font.footnote
        statusLabel.textColor = .tertiaryLabelColor
        addSubview(statusLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        addSubview(spinner)

        errorLabel.font = Theme.Font.footnote
        errorLabel.textColor = .systemOrange
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.isHidden = true
        addSubview(errorLabel)

        resultLabel.font = Theme.Font.footnote
        resultLabel.textColor = .secondaryLabelColor
        addSubview(resultLabel)

        copyButton.title = "复制"
        copyButton.isBordered = false
        copyButton.font = Theme.Font.caption
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

    private func configureCard(_ card: FillView) {
        card.fill = .textBackgroundColor
        card.cornerRadius = Theme.Radius.medium
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
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
        sourceTextView.font = Theme.Font.body
        sourceTextView.textColor = .labelColor
        sourceTextView.drawsBackground = false
        sourceTextView.textContainerInset = NSSize(width: Theme.Spacing.m, height: Theme.Spacing.m)
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
        resultTextView.textContainerInset = NSSize(width: Theme.Spacing.m, height: Theme.Spacing.m)
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

        // 流式输出每个 token 都会发布一次，按 60ms 合批，避免高频重建富文本
        model.$results
            .collect(.byTime(RunLoop.main, .milliseconds(60)))
            .receive(on: RunLoop.main)
            .sink { [weak self] batches in
                guard batches.last != nil else { return }
                self?.updateResults()
            }
            .store(in: &cancellables)

        model.$isTranslating
            .receive(on: RunLoop.main)
            .sink { [weak self] translating in
                self?.updateTranslating()
                // 翻译结束、结果已经落地，这时请求体与排版中间态都没人引用了，顺势归还给系统
                guard !translating else { return }
                DispatchQueue.main.async { MemoryPressure.relieve() }
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
        let topHeight: CGFloat = 36

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

        let headerY = topHeight + 8
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
            x: width - padding - 76,
            y: toolY,
            width: 76,
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
        // 文本容器宽度到这里才是最终值，分隔线宽度只能在这之后对齐
        updateDividerWidth()
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
        updateCopyMenuAffordance()

        if model.results.isEmpty {
            let text = model.isTranslating ? "翻译中…" : "翻译结果会显示在这里"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Theme.Font.body,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            resultTextView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: attributes)
            )
            copyButton.isEnabled = false
            return
        }

        let output = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let showTitles = model.results.count > 1
        dividerAttachments.removeAll()
        dividerBuiltWidth = dividerWidth()
        for (index, result) in model.results.enumerated() {
            if index > 0 {
                let (divider, attachment) = sectionDivider()
                dividerAttachments.append((attachment, output.length))
                output.append(divider)
            }
            if showTitles {
                let header = NSMutableParagraphStyle()
                header.paragraphSpacing = Theme.Spacing.xs
                output.append(NSAttributedString(
                    string: result.title + "\n",
                    attributes: [
                        .font: Theme.Font.footnoteStrong,
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: header,
                    ]
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
                    .font: Theme.Font.body,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]
            ))
            if index < model.results.count - 1 {
                // 段落样式跟的是段落结束符，先补换行结束本节，分隔段才能单独成段
                output.append(NSAttributedString(
                    string: "\n",
                    attributes: [.font: Theme.Font.body, .paragraphStyle: paragraph]
                ))
            }
        }

        resultTextView.textStorage?.setAttributedString(output)
        // 只在每轮翻译开始时回到顶部，流式更新期间保留用户滚动位置。
        if !didScrollForRun {
            resultTextView.scrollToBeginningOfDocument(nil)
            didScrollForRun = true
        }
        copyButton.isEnabled = !model.primaryText.isEmpty
        needsLayout = true
    }

    /// 多服务结果之间的分隔线：NSTextBlock 的边线在 NSTextView 里画不出来，
    /// 改成 1pt 高的可拉伸图片附件，宽度随版心变化时由 layout() 更新。
    /// 线只建一次图案：流式输出会反复重建富文本，每次新建 NSImage 会白白攒位图
    private static let dividerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            Theme.separator.setFill()
            rect.fill()
            return true
        }
        // 不缓存位图，深浅色切换时 drawingHandler 才会重新取色
        image.cacheMode = .never
        return image
    }()

    private func sectionDivider() -> (NSAttributedString, NSTextAttachment) {
        let width = dividerWidth()
        let attachment = NSTextAttachment()
        attachment.image = Self.dividerImage
        // 行首自带 lineFragmentPadding，附件左移同样的距离才能和版心左右对齐
        let padding = resultTextView.textContainer?.lineFragmentPadding ?? 0
        attachment.bounds = NSRect(x: -padding, y: 0, width: width, height: 1)

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = Theme.Spacing.m
        style.paragraphSpacing = Theme.Spacing.m
        style.minimumLineHeight = 1
        style.maximumLineHeight = 1

        let divider = NSMutableAttributedString(attachment: attachment)
        divider.append(NSAttributedString(
            string: "\n",
            attributes: [.font: Theme.Font.caption, .paragraphStyle: style]
        ))
        divider.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: divider.length)
        )
        return (divider, attachment)
    }

    /// 分隔线宽度取文本容器宽度，与正文等宽
    private func dividerWidth() -> CGFloat {
        resultTextView.textContainer?.containerSize.width ?? 0
    }

    /// 弹窗可缩放，版心变化后把分隔线附件拉到新宽度
    private func updateDividerWidth() {
        guard !dividerAttachments.isEmpty else { return }
        let width = dividerWidth()
        guard abs(width - dividerBuiltWidth) > 0.5 else { return }
        dividerBuiltWidth = width
        for (attachment, index) in dividerAttachments {
            attachment.bounds.size.width = width
            resultTextView.layoutManager?.invalidateLayout(
                forCharacterRange: NSRange(location: index, length: 1),
                actualCharacterRange: nil
            )
        }
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


/// 弹窗主按钮：系统 bezel 在小尺寸下偏灰、圆角也不贴，这里自绘强调色圆角
final class PrimaryButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let base = NSColor.controlAccentColor
        let pressed = isHighlighted ? 0.18 : 0
        let fill = isEnabled
            ? (base.blended(withFraction: pressed, of: .black) ?? base)
            : base.withAlphaComponent(0.35)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let font = Theme.Font.button
        let text = title as NSString
        let textSize = text.size(withAttributes: [.font: font])
        let iconSize = NSSize(width: 13, height: 13)
        let gap: CGFloat = 5
        let iconWidth = image == nil ? 0 : iconSize.width + gap
        var x = (bounds.width - iconWidth - textSize.width) / 2
        if let image {
            image.draw(in: NSRect(
                x: x,
                y: (bounds.height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            ))
            x += iconWidth
        }
        text.draw(
            at: NSPoint(x: x, y: (bounds.height - textSize.height) / 2),
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.75),
            ]
        )
    }
}

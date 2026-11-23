// 权限引导：主窗列出两项权限，点授权后另起一个跟随系统设置的小浮条，轮询到授权即收。
// 不处理：系统自带的「退出并重新打开」TCC 提示；截图走独立子进程，授权后无需重启应用。
import AppKit

enum PermissionKind: CaseIterable {
    case accessibility
    case screenRecording

    var title: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .screenRecording: return "屏幕录制"
        }
    }

    var detail: String {
        switch self {
        case .accessibility: return "读取选中文本"
        case .screenRecording: return "截图翻译与 OCR"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }

    var settingsURL: URL? {
        let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: return SelectionReader.hasAccessibilityPermission
        case .screenRecording: return OCREngine.hasScreenPermission
        }
    }

    /// 两项的拖动目标列表不同，步骤文案必须写清允许什么，避免用户拖错窗格。
    var steps: [String] {
        let allow = self == .accessibility ? "以允许控制你的电脑" : "以允许录屏与系统声音"
        return [
            "1、如果列表里已有 Mote，请先选中它，再点下方的「−」号删除",
            "2、再把 Mote 拖到列表里，\(allow)",
        ]
    }
}

private final class PermissionRow {
    let view: NSView
    let status: NSTextField
    let button: NSButton

    init(view: NSView, status: NSTextField, button: NSButton) {
        self.view = view
        self.status = status
        self.button = button
    }
}

final class PermissionGuideController: NSObject, NSWindowDelegate {
    static let shared = PermissionGuideController()

    private var window: PermissionPanel?
    private var rows: [PermissionKind: PermissionRow] = [:]
    private var guidance: GuidancePanel?
    private var pending: PermissionKind?
    private var pollTimer: Timer?
    private var activeObserver: NSObjectProtocol?

    func show() {
        // 已经在等授权时重新打开：收起浮条，回到主窗重新选
        stopPolling()
        guidance?.close()
        guidance = nil
        pending = nil

        let window = self.window ?? makeWindow()
        refresh()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppActivation.activate(window)
    }

    func windowWillClose(_ notification: Notification) {
        (notification.object as? NSWindow)?.contentView = nil
        stopPolling()
        guidance?.close()
        guidance = nil
        pending = nil
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
        window = nil
        rows = [:]
        AppActivation.restoreAccessoryPolicy()
    }

    // MARK: - 主窗

    private func makeWindow() -> PermissionPanel {
        let window = PermissionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.title = "Mote 权限"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = makeContentView()
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
        self.window = window

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPending()
        }
        return window
    }

    private func makeContentView() -> NSView {
        let content = NSView()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(icon)

        let title = NSTextField(labelWithString: "授予 Mote 权限")
        title.font = Theme.Font.large
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let subtitle = NSTextField(
            labelWithString: "Mote 需要你的许可才能使用，请查看并授权。"
        )
        subtitle.font = Theme.Font.footnote
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subtitle)

        let rowViews = PermissionKind.allCases.map { kind -> NSView in
            let row = permissionRow(for: kind)
            rows[kind] = row
            return row.view
        }

        // 复用设置页的卡片：同一套圆角与填充，深浅色都不会白底压白底
        let card = CardView(views: rowViews)
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(card)
        for row in rows.values {
            row.view.widthAnchor.constraint(equalTo: card.widthAnchor).isActive = true
        }

        let bottomHint = NSTextField(labelWithString: "授权后回到 Mote 会自动刷新状态。")
        bottomHint.font = Theme.Font.footnote
        bottomHint.textColor = .secondaryLabelColor
        bottomHint.alignment = .center
        bottomHint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bottomHint)

        NSLayoutConstraint.activate([
            // 宽度写死，高度由内容撑开，窗口尺寸按 fittingSize 取
            content.widthAnchor.constraint(equalToConstant: 480),

            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            icon.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 10),
            title.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            card.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),

            bottomHint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
            bottomHint.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            bottomHint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])

        return content
    }

    private func permissionRow(for kind: PermissionKind) -> PermissionRow {
        let icon = NSImageView(
            image: NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                ?? NSImage()
        )
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let titleLabel = NSTextField(labelWithString: kind.title)
        titleLabel.font = Theme.Font.body
        let detailLabel = NSTextField(labelWithString: kind.detail)
        detailLabel.font = Theme.Font.footnote
        detailLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let granted = kind.isGranted
        let status = NSTextField(labelWithString: granted ? "已授权" : "未授权")
        status.font = Theme.Font.footnote
        status.textColor = granted ? .systemGreen : .systemOrange
        status.alignment = .right
        status.translatesAutoresizingMaskIntoConstraints = false
        status.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let button = NSButton(
            title: granted ? "已授权" : "授权",
            target: self,
            action: #selector(grant(_:))
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = Theme.Font.footnote
        // 已授权只留状态文字，避免和左侧「已授权」重复
        button.isHidden = granted
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, labels, spacer, status, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        return PermissionRow(view: row, status: status, button: button)
    }

    @objc private func grant(_ sender: NSButton) {
        guard let kind = rows.first(where: { $0.value.button === sender })?.key else { return }
        request(kind)
    }

    // MARK: - 授权流程

    private func request(_ kind: PermissionKind) {
        if kind.isGranted {
            finish(kind)
            return
        }
        startGuiding(kind)
    }

    /// 设置页等其它入口复用同一套流程，避免同一件事在两个入口表现不同
    func guide(_ kind: PermissionKind) {
        guard !kind.isGranted else { return }
        startGuiding(kind)
    }

    private func startGuiding(_ kind: PermissionKind) {
        // 不管从哪个入口进来都把主窗建好：授权完还差一项时要靠它回来提示
        let window = self.window ?? makeWindow()
        refresh()
        // 不调系统请求接口：那会弹「想使用辅助功能控制这台电脑」之类的一堆系统框，
        // 直接打开设置页，靠浮条里的拖动卡片把 Mote 加进列表即可。
        if let url = kind.settingsURL {
            NSWorkspace.shared.open(url)
        }
        stopPolling()
        guidance?.close()
        pending = kind
        let panel = GuidancePanel(steps: kind.steps)
        guidance = panel
        positionGuidance()
        panel.present()
        startPolling()
        // 主窗让位给系统设置，浮条贴着设置窗口提示拖动
        window.orderOut(nil)
    }

    private func checkPending() {
        refresh()
        guard let pending, pending.isGranted else { return }
        finish(pending)
    }

    /// 系统设置里勾选没有回调，只能轮询。
    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let pending = self.pending else { return }
            // 授权状态要在子进程里查才准，放后台刷新，这轮读上一轮的结果
            PermissionProbe.refreshInBackground()
            if pending.isGranted {
                self.finish(pending)
            } else {
                self.positionGuidance()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// 授权一项就收浮条；两项都齐才关主窗，否则主窗留着让用户点另一项。
    private func finish(_ granted: PermissionKind) {
        stopPolling()
        pending = nil
        guidance?.close()
        guidance = nil
        refresh()
        guard let window else { return }
        // 主窗之前让位给了系统设置，这里叫回来：还差一项让用户接着点，
        // 两项都齐则作为完成反馈短暂露一下再收，避免窗口莫名消失
        window.orderFrontRegardless()
        if PermissionKind.allCases.allSatisfy({ $0.isGranted }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.window?.close()
            }
        }
    }

    private func refresh() {
        for kind in PermissionKind.allCases {
            guard let row = rows[kind] else { continue }
            let granted = kind.isGranted
            row.status.stringValue = granted ? "已授权" : "未授权"
            row.status.textColor = granted ? .systemGreen : .systemOrange
            row.button.title = "授权"
            row.button.isHidden = granted
        }
    }

    // MARK: - 浮条定位

    /// 系统设置窗口的屏幕坐标（AppKit 左下原点）；窗口还没建好时返回 nil。
    private func settingsWindowFrame() -> NSRect? {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]],
            let primaryTop = NSScreen.screens.first?.frame.maxY
        else { return nil }

        for info in list {
            guard
                let owner = info[kCGWindowOwnerName as String] as? String,
                owner == "系统设置" || owner == "System Settings",
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                rect.width > 240, rect.height > 240
            else { continue }
            return NSRect(
                x: rect.minX,
                y: primaryTop - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
        return nil
    }

    private func positionGuidance() {
        guard let panel = guidance else { return }
        guard let anchor = settingsWindowFrame() else {
            panel.centerOnMainScreen()
            return
        }

        let size = panel.frame.size
        let visible = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame
        // 默认贴在设置窗口右下方右对齐，下方放不下就翻到上方
        var origin = NSPoint(x: anchor.maxX - size.width, y: anchor.minY - size.height - 8)
        if let visible, origin.y < visible.minY {
            origin.y = anchor.maxY + 8
        }
        if let visible {
            origin.x = min(
                max(origin.x, visible.minX + 8),
                visible.maxX - size.width - 8
            )
            origin.y = min(
                max(origin.y, visible.minY + 8),
                visible.maxY - size.height - 8
            )
        }
        panel.setFrameOrigin(origin)
    }
}

private final class PermissionPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// 授权期间贴在系统设置旁的提示浮条：不吃焦点，不挡列表。
private final class GuidancePanel: NSPanel {
    init(steps: [String]) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 424, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let content = makeContentView(steps: steps)
        contentView = content
        setContentSize(content.fittingSize)
    }

    func present() {
        orderFrontRegardless()
    }

    func centerOnMainScreen() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(
            NSPoint(
                x: screen.midX - frame.width / 2,
                y: screen.midY - frame.height / 2
            )
        )
    }

    private func makeContentView(steps: [String]) -> NSView {
        let root = NSView()

        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor =
            NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)

        let arrow = NSImageView(
            image: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
                ?? NSImage()
        )
        arrow.contentTintColor = .secondaryLabelColor
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let stepLabels = steps.map { text -> NSTextField in
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = Theme.Font.footnote
            label.textColor = .secondaryLabelColor
            return label
        }
        let stepStack = NSStackView(views: stepLabels)
        stepStack.orientation = .vertical
        stepStack.alignment = .leading
        stepStack.spacing = 2
        stepStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [arrow, stepStack])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 8

        let chip = PermissionDragChip()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let stack = NSStackView(views: [header, chip])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            card.widthAnchor.constraint(equalToConstant: 424),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            chip.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stepStack.widthAnchor.constraint(equalTo: chip.widthAnchor, constant: -22),
        ])

        return root
    }
}

/// 可拖进系统设置授权列表的卡片。
private final class PermissionDragChip: NSView, NSDraggingSource {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let name = NSTextField(labelWithString: "Mote")
        name.font = .systemFont(ofSize: 12, weight: .medium)

        let hint = NSTextField(labelWithString: "拖动此处")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .systemRed

        let handIcon = NSImageView(
            image: NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
                ?? NSImage()
        )
        handIcon.contentTintColor = .tertiaryLabelColor
        handIcon.translatesAutoresizingMaskIntoConstraints = false
        handIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, name, spacer, hint, handIcon])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let image = NSApp.applicationIconImage else { return }
        // 直接以 app 包 URL 作为拖拽载荷，系统设置接受这种文件拖入
        let dragging = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        dragging.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}

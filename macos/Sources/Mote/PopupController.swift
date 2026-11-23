// 鼠标附近的悬浮翻译窗：负责显示、定位和焦点归还；不处理选区读取。
import AppKit

final class MotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PopupController {
    static let size = NSSize(width: 520, height: 420)

    private let panel: MotePanel
    private let model: PopupViewModel
    private let store: SettingsStore
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private var forcedRegularPolicy = false
    private var contentConfigured = false
    private var popupContent: PopupContentView?
    private(set) var isVisible = false
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?

    private static let originXKey = "MotePopupOriginX"
    private static let originYKey = "MotePopupOriginY"

    init(store: SettingsStore, service: TranslationService, history: HistoryStore) {
        self.store = store
        model = PopupViewModel(store: store, service: service, history: history)
        panel = MotePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 460, height: 340)
        panel.maxSize = NSSize(width: 900, height: 800)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 只有弹窗可见时才吞 Esc，否则其它窗口的 Esc（如设置窗取消）会被一并吃掉
            // 只有弹窗自己拿着焦点时才吞 Esc，避免抢走设置窗等其它窗口的取消键
            guard let self, self.isVisible, self.panel.isKeyWindow, event.keyCode == 53 else { return event }
            self.hide()
            return nil
        }

        // 点击其他应用或窗口时自动收起，但不抢回焦点。
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.hide(restoreFocus: false)
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.saveOrigin()
        }
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }

    func show(sourceText: String) {
        previousApplication = NSWorkspace.shared.frontmostApplication
        model.sourceText = sourceText
        model.results = []
        model.errorMessage = nil
        model.didCopy = false
        model.focusToken += 1
        isVisible = true

        configureContentIfNeeded()
        applyConfiguredSize()
        if let origin = savedOrigin {
            panel.setFrameOrigin(origin)
            clampToVisibleScreen()
        } else {
            positionDefault()
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        popupContent?.focusEditor()
        DispatchQueue.main.async { [weak self] in
            self?.popupContent?.focusEditor()
        }
        activateAppIfNeeded()

        if !sourceText.isEmpty {
            model.translate()
        }
    }

    func hide(restoreFocus: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        model.cancel()
        panel.orderOut(nil)
        // AppKit 子视图在关闭时也释放，避免多次使用后内存只涨不降。
        panel.contentView = nil
        popupContent = nil
        contentConfigured = false
        MemoryPressure.relieve()

        if restoreFocus,
           let previousApplication,
           previousApplication != NSRunningApplication.current {
            AppActivation.activate(previousApplication)
        }
        previousApplication = nil

        if forcedRegularPolicy {
            NSApp.setActivationPolicy(.accessory)
            forcedRegularPolicy = false
        }
    }

    func showPlaceholder(message: String) {
        show(sourceText: "")
        model.errorMessage = message
    }

    // 弹窗内容按需创建，保持菜单栏常驻时只加载 AppKit。
    private func configureContentIfNeeded() {
        guard !contentConfigured else { return }
        contentConfigured = true

        let content = PopupContentView(
            model: model,
            store: store,
            onClose: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onOpenHistory: { [weak self] in self?.onOpenHistory?() }
        )
        content.autoresizingMask = [.width, .height]
        popupContent = content
        panel.contentView = content
    }

    private var savedOrigin: NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.originXKey) != nil,
              defaults.object(forKey: Self.originYKey) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: Self.originXKey),
            y: defaults.double(forKey: Self.originYKey)
        )
    }

    private func saveOrigin() {
        guard isVisible, !panel.isMiniaturized else { return }
        UserDefaults.standard.set(panel.frame.minX, forKey: Self.originXKey)
        UserDefaults.standard.set(panel.frame.minY, forKey: Self.originYKey)
    }

    private func applyConfiguredSize() {
        let width = min(max(store.config.popupWidth, 460), 900)
        let height = min(max(store.config.popupHeight, 340), 800)
        var frame = panel.frame
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: false)
    }

    private func activateAppIfNeeded() {
        AppActivation.activate(NSApp)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.isVisible, !NSApp.isActive else { return }
            NSApp.setActivationPolicy(.regular)
            self.forcedRegularPolicy = true
            AppActivation.activate(NSApp)
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.makeKey()
        }
    }

    private func clampToVisibleScreen() {
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var clamped = frame
        clamped.size.width = min(max(clamped.width, 460), visible.width)
        clamped.size.height = min(max(clamped.height, 340), visible.height)
        clamped.origin.x = min(max(clamped.minX, visible.minX), visible.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.minY, visible.minY), visible.maxY - clamped.height)
        if clamped != frame {
            panel.setFrame(clamped, display: false)
        }
    }

    private func positionDefault() {
        guard let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return
        }
        let size = panel.frame.size
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.midY - size.height / 2 + 80
        panel.setFrameOrigin(
            NSPoint(
                x: max(visibleFrame.minX + 8, x),
                y: min(y, visibleFrame.maxY - size.height - 20)
            )
        )
    }
}


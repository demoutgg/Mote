// 鼠标附近的悬浮翻译窗：负责显示、定位和焦点归还；不处理选区读取。
import AppKit
import SwiftUI

final class LingolitePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PopupController {
    static let size = NSSize(width: 520, height: 420)

    private let panel: LingolitePanel
    private let model: PopupViewModel
    private let store: SettingsStore
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private var resizeStartFrame: NSRect?
    private var forcedRegularPolicy = false
    private(set) var isVisible = false
    var onOpenSettings: (() -> Void)?

    private static let originXKey = "LingolitePopupOriginX"
    private static let originYKey = "LingolitePopupOriginY"

    init(store: SettingsStore, service: TranslationService) {
        self.store = store
        model = PopupViewModel(store: store, service: service)
        panel = LingolitePanel(
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
        let view = PopupView(
            model: model,
            store: store,
            onClose: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onResize: { [weak self] translation in self?.resize(by: translation) },
            onResizeEnd: { [weak self] in self?.finishResize() }
        )
        panel.contentView = NSHostingView(rootView: view)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
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

        applyConfiguredSize()
        if let origin = savedOrigin {
            panel.setFrameOrigin(origin)
            clampToVisibleScreen()
        } else {
            positionDefault()
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
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

    func resize(by translation: CGSize) {
        if resizeStartFrame == nil {
            resizeStartFrame = panel.frame
        }
        guard let start = resizeStartFrame else { return }

        let width = min(max(start.width + translation.width, 460), 900)
        let height = min(max(start.height - translation.height, 340), 800)
        var frame = start
        frame.origin.y = start.maxY - height
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    private func finishResize() {
        resizeStartFrame = nil
        store.config.popupWidth = Double(panel.frame.width)
        store.config.popupHeight = Double(panel.frame.height)
        store.save()
        saveOrigin()
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


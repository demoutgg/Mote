// 鼠标附近的悬浮翻译窗：负责显示、定位和焦点归还；不处理选区读取。
import AppKit
import SwiftUI

final class LingolitePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PopupController {
    static let size = NSSize(width: 480, height: 340)

    private let panel: LingolitePanel
    private let model: PopupViewModel
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private(set) var isVisible = false

    init(store: SettingsStore, service: TranslationService) {
        model = PopupViewModel(store: store, service: service)
        panel = LingolitePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
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

        let view = PopupView(model: model, store: store) { [weak self] in
            self?.hide()
        }
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
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }

    func show(sourceText: String) {
        previousApplication = NSWorkspace.shared.frontmostApplication
        model.sourceText = sourceText
        model.output = ""
        model.errorMessage = nil
        isVisible = true
        positionNearMouse()

        AppActivation.activate(NSApp)
        panel.makeKeyAndOrderFront(nil)

        if sourceText.isEmpty {
            if !SelectionReader.hasAccessibilityPermission {
                model.errorMessage = "没有拿到选中文本。请先授予“辅助功能”权限，或直接在上方输入。"
            }
        } else {
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
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouse, $0.frame, false)
        } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if origin.y < visibleFrame.minY + 8 {
            origin.y = mouse.y + 14
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}


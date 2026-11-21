import AppKit
import SwiftUI

final class LingolitePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PopupController {
    private let panel: LingolitePanel
    private let model: PopupViewModel
    private var escapeMonitor: Any?

    init(store: SettingsStore, translationService: TranslationService) {
        model = PopupViewModel(service: translationService)
        panel = LingolitePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
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
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    func show(sourceText: String, autoTranslate: Bool) {
        model.sourceText = sourceText
        model.output = ""
        model.errorMessage = nil
        positionNearMouse()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if autoTranslate {
            model.translate()
        }
    }

    func hide() {
        model.cancel()
        panel.orderOut(nil)
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouse, $0.frame, false)
        } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}


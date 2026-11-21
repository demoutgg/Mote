// 轻量提示条：在鼠标附近短暂显示一行结果，不抢焦点。
import AppKit

final class ToastController {
    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    func show(_ message: String) {
        hideWorkItem?.cancel()
        window?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding = NSSize(width: 14, height: 9)
        let size = NSSize(
            width: max(label.frame.width + padding.width * 2, 70),
            height: label.frame.height + padding.height * 2
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        container.layer?.cornerRadius = size.height / 2
        container.layer?.masksToBounds = true

        label.frame = NSRect(
            x: padding.width,
            y: (size.height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )
        container.addSubview(label)
        panel.contentView = container

        position(panel, size: size)
        panel.orderFrontRegardless()
        window = panel

        let item = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func position(_ panel: NSWindow, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 20)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(origin.y, visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}

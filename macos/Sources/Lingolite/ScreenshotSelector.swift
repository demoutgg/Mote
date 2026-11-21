// 全屏框选遮罩：暗色背景 + 可拖拽选框，返回主屏坐标系中的截图区域。
import AppKit

final class ScreenshotSelector {
    private var window: NSWindow?
    private var monitor: Any?

    func start(completion: @escaping (CGRect?) -> Void) {
        guard window == nil else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else {
            completion(nil)
            return
        }

        let overlay = SelectorWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.level = .screenSaver
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.screenOrigin = screen.frame.origin
        view.mainScreenTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        view.onFinish = { [weak self] rect in
            self?.dismiss()
            completion(rect)
        }
        overlay.contentView = view
        overlay.delegate = nil

        window = overlay
        NSApp.setActivationPolicy(.regular)
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(view)
        AppActivation.activate(NSApp)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            completion(nil)
            return nil
        }
    }

    private func dismiss() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        AppActivation.restoreAccessoryPolicy()
    }
}

private final class SelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    var screenOrigin: NSPoint = .zero
    var mainScreenTop: CGFloat = 0
    var onFinish: ((CGRect?) -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let selection = selectionRect, selection.width >= 8, selection.height >= 8 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        onFinish?(globalRect(for: selection))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let selection = selectionRect
        let shade = NSBezierPath(rect: bounds)
        if let selection {
            shade.append(NSBezierPath(rect: selection))
        }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(selection == nil ? 0.28 : 0.36).setFill()
        shade.fill()

        if let selection, selection.width > 0, selection.height > 0 {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()

            let handleSize: CGFloat = 7
            let points = [
                NSPoint(x: selection.minX, y: selection.minY),
                NSPoint(x: selection.maxX, y: selection.minY),
                NSPoint(x: selection.minX, y: selection.maxY),
                NSPoint(x: selection.maxX, y: selection.maxY),
            ]
            NSColor.white.setFill()
            for point in points {
                let rect = NSRect(
                    x: point.x - handleSize / 2,
                    y: point.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                NSBezierPath(rect: rect).fill()
            }

            drawSizeLabel(for: selection)
        } else {
            drawHint()
        }

        context.flush()
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        ).intersection(bounds)
    }

    private func globalRect(for rect: NSRect) -> CGRect {
        let cocoa = NSRect(
            x: screenOrigin.x + rect.minX,
            y: screenOrigin.y + rect.minY,
            width: rect.width,
            height: rect.height
        )
        return CGRect(
            x: cocoa.minX,
            y: mainScreenTop - cocoa.maxY,
            width: cocoa.width,
            height: cocoa.height
        )
    }

    private func drawSizeLabel(for rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = NSPoint(
            x: rect.minX + 6,
            y: rect.maxY + 6
        )
        if origin.y + size.height + 8 > bounds.maxY {
            origin.y = rect.maxY - size.height - 10
        }

        let background = NSRect(
            x: origin.x - 5,
            y: origin.y - 3,
            width: size.width + 10,
            height: size.height + 6
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func drawHint() {
        let text = "拖动框选要翻译的区域 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        let background = NSRect(
            x: origin.x - 16,
            y: origin.y - 10,
            width: size.width + 32,
            height: size.height + 20
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: background, xRadius: 10, yRadius: 10).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

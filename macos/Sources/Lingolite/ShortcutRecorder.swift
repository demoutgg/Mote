// 快捷键录制控件：点击后按下组合键，Esc 取消。
import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    var binding: KeyBinding
    var onChange: (KeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.binding = binding
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.binding = binding
        view.onChange = onChange
        view.needsDisplay = true
    }
}

final class RecorderView: NSView {
    var binding = ShortcutAction.input.defaultBinding
    var onChange: ((KeyBinding) -> Void)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 6,
            yRadius: 6
        )
        (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.14)
            : NSColor.controlBackgroundColor
        ).setFill()
        path.fill()

        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "按下快捷键…" : binding.display
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            needsDisplay = true
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonModifiers = KeyBinding.carbonModifiers(from: flags)
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }

        let newBinding = KeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers,
            display: KeyBinding.displayString(flags: flags, event: event),
            keyEquivalent: event.charactersIgnoringModifiers?.lowercased() ?? ""
        )
        binding = newBinding
        isRecording = false
        onChange?(newBinding)
        needsDisplay = true
    }
}

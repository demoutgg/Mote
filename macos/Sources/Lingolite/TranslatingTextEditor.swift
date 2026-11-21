// 原生输入框包装：Enter 翻译、⌘/⌥/⇧+Enter 换行，并保留系统级复制粘贴。
import AppKit
import SwiftUI

struct TranslatingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 84))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.placeholder = placeholder
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.string = text
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        context.coordinator.parent = self
        textView.placeholder = placeholder

        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TranslatingTextEditor
        weak var textView: NSTextView?
        var lastFocusToken = Int.min

        init(_ parent: TranslatingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let flags = NSApp.currentEvent?
                .modifierFlags
                .intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.command) || flags.contains(.option) || flags.contains(.shift) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            }

            parent.onSubmit()
            return true
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholder = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let padding = textContainerInset
        let rect = NSRect(
            x: padding.width + 4,
            y: padding.height,
            width: max(bounds.width - padding.width * 2 - 8, 0),
            height: max(bounds.height - padding.height * 2, 0)
        )
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
    }
}

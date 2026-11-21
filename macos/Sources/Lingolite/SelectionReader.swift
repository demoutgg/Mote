import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

enum SelectionReader {
    static func selectedText() -> String? {
        if let text = accessibilitySelectedText(), !text.isEmpty {
            return text
        }
        return clipboardFallback()
    }

    private static func accessibilitySelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusedResult == .success, let focusedElement else { return nil }

        let element = focusedElement as! AXUIElement
        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard selectedResult == .success else { return nil }
        return selectedValue as? String
    }

    /// 兼容不支持 AXSelectedText 的应用；会短暂占用剪贴板，随后恢复原内容。
    private static func clipboardFallback() -> String? {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        sendCommandC()
        usleep(180_000)

        let captured = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
        return captured
    }

    private static func sendCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}


// 读取前台应用选区：优先 Accessibility，失败时模拟 ⌘C 并完整还原剪贴板；不处理 OCR。
import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

enum SelectionReader {
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// 在后台队列读取，避免模拟复制时的等待阻塞主线程刷新界面。
    static func read(completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = accessibilitySelectedText() ?? clipboardFallback() ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(trimmed)
            }
        }
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

    /// 部分应用不暴露 AXSelectedText，只能模拟复制。复制期间会短暂改写剪贴板，
    /// 结束后按原始 pasteboard items 还原，包含图片和文件列表。
    private static func clipboardFallback() -> String? {
        guard hasAccessibilityPermission else { return nil }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
        let changeCount = pasteboard.changeCount

        sendCommandC()

        var captured: String?
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount {
                captured = pasteboard.string(forType: .string)
                break
            }
            usleep(8_000)
        }

        guard captured != nil else { return nil }

        pasteboard.clearContents()
        if !savedItems.isEmpty {
            pasteboard.writeObjects(savedItems)
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


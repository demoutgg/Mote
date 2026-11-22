// 快捷键模型与默认值：保存 Carbon 修饰键和按键码，同时保留展示文本。
import AppKit
import Carbon.HIToolbox

struct KeyBinding: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
    var keyEquivalent: String = ""

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    static func displayString(flags: NSEvent.ModifierFlags, event: NSEvent) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += keyName(for: event)
        return text
    }

    private static func keyName(for event: NSEvent) -> String {
        if let special = specialKeys[UInt16(event.keyCode)] {
            return special
        }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }
        return "Key\(event.keyCode)"
    }

    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
    ]
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case input
    case selection
    case clipboard
    case screenshot
    case screenshotOCR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input:
            return "输入翻译"
        case .selection:
            return "选中翻译"
        case .clipboard:
            return "剪贴翻译"
        case .screenshot:
            return "截图翻译"
        case .screenshotOCR:
            return "截图 OCR"
        }
    }

    var detail: String {
        switch self {
        case .input:
            return "打开空弹窗手动输入"
        case .selection:
            return "读取当前选中的文本"
        case .clipboard:
            return "翻译剪贴板中的文本"
        case .screenshot:
            return "框选区域，识别后翻译"
        case .screenshotOCR:
            return "框选区域，识别后复制"
        }
    }

    var hotKeyID: UInt32 {
        switch self {
        case .input:
            return 1
        case .selection:
            return 2
        case .clipboard:
            return 3
        case .screenshot:
            return 4
        case .screenshotOCR:
            return 5
        }
    }

    var defaultBinding: KeyBinding {
        switch self {
        case .input:
            return KeyBinding(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(optionKey),
                display: "⌥A",
                keyEquivalent: "a"
            )
        case .selection:
            return KeyBinding(
                keyCode: UInt32(kVK_ANSI_D),
                modifiers: UInt32(optionKey),
                display: "⌥D",
                keyEquivalent: "d"
            )
        case .clipboard:
            return KeyBinding(
                keyCode: UInt32(kVK_ANSI_V),
                modifiers: UInt32(optionKey),
                display: "⌥V",
                keyEquivalent: "v"
            )
        case .screenshot:
            return KeyBinding(
                keyCode: UInt32(kVK_ANSI_S),
                modifiers: UInt32(optionKey),
                display: "⌥S",
                keyEquivalent: "s"
            )
        case .screenshotOCR:
            return KeyBinding(
                keyCode: UInt32(kVK_ANSI_S),
                modifiers: UInt32(optionKey) | UInt32(shiftKey),
                display: "⇧⌥S",
                keyEquivalent: "s"
            )
        }
    }
}

extension AppConfig {
    func binding(for action: ShortcutAction) -> KeyBinding {
        keyBindings[action.rawValue] ?? action.defaultBinding
    }

    mutating func setBinding(_ binding: KeyBinding, for action: ShortcutAction) {
        keyBindings[action.rawValue] = binding
    }

    mutating func resetBinding(for action: ShortcutAction) {
        keyBindings.removeValue(forKey: action.rawValue)
    }
}

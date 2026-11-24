// 菜单栏应用没有主菜单，⌘W 默认不生效；这里补上 Esc 与 ⌘W 关窗，其余按键照常交给系统。
import AppKit

final class DismissibleWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

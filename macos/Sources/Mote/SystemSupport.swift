// 兼容 macOS 13/14 的应用激活封装；不处理窗口层级和焦点策略。
import AppKit

enum AppActivation {
    static func activate(_ application: NSApplication) {
        application.activate(ignoringOtherApps: true)
    }

    static func activate(_ application: NSRunningApplication) {
        _ = application.activate(options: [.activateIgnoringOtherApps])
    }

    /// 普通窗口先直接激活；被系统拒绝时临时切到 regular 策略，保证窗口能接收输入。
    static func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            // 窗口可能已被主动隐藏（如授权时让位给系统设置），不能再拉回来
            guard !NSApp.isActive, window.isVisible else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeKey()
        }
    }

    static func restoreAccessoryPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }
}

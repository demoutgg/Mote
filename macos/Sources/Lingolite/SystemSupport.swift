// 兼容 macOS 13/14 的应用激活封装；不处理窗口层级和焦点策略。
import AppKit

enum AppActivation {
    static func activate(_ application: NSApplication) {
        if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(ignoringOtherApps: true)
        }
    }

    static func activate(_ application: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            _ = application.activate()
        } else {
            _ = application.activate(options: [])
        }
    }
}

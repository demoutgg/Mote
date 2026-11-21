// 设置窗口的生命周期：每次打开都用当前配置重建草稿，关闭后释放。
import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private var window: NSWindow?

    init(store: SettingsStore) {
        self.store = store
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            AppActivation.activate(NSApp)
            return
        }

        let settingsView = SettingsView(store: store) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lingolite Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        AppActivation.activate(NSApp)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}


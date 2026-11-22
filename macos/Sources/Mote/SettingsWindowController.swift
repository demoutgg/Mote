// 设置窗口的生命周期：每次打开都用当前配置重建草稿，关闭后释放。
import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let history: HistoryStore
    private var window: NSWindow?
    var onStatusIconPreview: ((String) -> Void)?

    init(store: SettingsStore, history: HistoryStore) {
        self.store = store
        self.history = history
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            AppActivation.activate(window)
            return
        }

        let settingsView = SettingsView(
            store: store,
            history: history,
            onStatusIconPreview: { [weak self] name in
                self?.onStatusIconPreview?(name)
            },
            onClose: { [weak self] in
                self?.window?.close()
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mote 设置"
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppActivation.activate(window)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onStatusIconPreview?(store.config.statusIcon)
        AppActivation.restoreAccessoryPolicy()
    }
}


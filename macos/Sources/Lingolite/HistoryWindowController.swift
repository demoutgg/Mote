// 历史记录窗口生命周期；关闭后释放窗口并恢复菜单栏应用策略。
import AppKit
import SwiftUI

final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private var window: NSWindow?

    init(store: HistoryStore) {
        self.store = store
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            AppActivation.activate(window)
            return
        }

        let view = HistoryView(store: store) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lingolite 历史记录"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 560, height: 440)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppActivation.activate(window)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivation.restoreAccessoryPolicy()
    }
}

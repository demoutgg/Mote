// 历史记录窗口生命周期；关闭后释放窗口并恢复菜单栏应用策略。
import AppKit

final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private var window: NSWindow?
    private var pane: HistoryPane?

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

        let window = DismissibleWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "历史记录"
        let pane = HistoryPane(store: store)
        self.pane = pane
        window.contentView = pane
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 560, height: 440)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppActivation.activate(window)
    }

    /// 菜单「清空历史记录…」的入口：先开窗，再复用历史页里的确认 sheet
    func confirmClear() {
        show()
        pane?.confirmClear()
    }

    func windowWillClose(_ notification: Notification) {
        (notification.object as? NSWindow)?.contentView = nil
        window = nil
        pane = nil
        AppActivation.restoreAccessoryPolicy()
    }
}

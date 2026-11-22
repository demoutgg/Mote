// 引导窗口生命周期：只在首次启动或手动打开时显示。
import AppKit
import SwiftUI

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let completedKey = "didCompleteOnboarding"

    private let store: SettingsStore
    private let onOpenSettings: () -> Void
    private var window: NSWindow?

    init(store: SettingsStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            AppActivation.activate(window)
            return
        }

        let view = OnboardingView(
            store: store,
            onOpenSettings: onOpenSettings,
            onFinish: { [weak self] in
                self?.finish()
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mote 使用指南"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppActivation.activate(window)
    }

    func windowWillClose(_ notification: Notification) {
        markCompleted()
        window = nil
        AppActivation.restoreAccessoryPolicy()
    }

    private func finish() {
        markCompleted()
        window?.close()
    }

    private func markCompleted() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }
}

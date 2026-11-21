// 应用入口：菜单栏、全局快捷键、权限引导；不含翻译业务逻辑。
import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var popupController: PopupController?
    private var settingsWindowController: SettingsWindowController?
    private var isReadingSelection = false

    private let settingsStore = SettingsStore()
    private let translationService = TranslationService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        popupController = PopupController(store: settingsStore, service: translationService)
        settingsWindowController = SettingsWindowController(store: settingsStore)

        hotKeyManager = HotKeyManager(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(optionKey)
        ) { [weak self] in
            self?.translateSelection()
        }
        if hotKeyManager?.register() != true {
            NSLog("Lingolite: failed to register global hotkey ⌥L")
        }

        requestAccessibilityIfNeeded()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Lingolite")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Lingolite"
        }

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Translate Selection  ⌥L", action: #selector(translateSelection)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(menuItem(title: "Accessibility Permission…", action: #selector(openAccessibilitySettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Lingolite", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func translateSelection() {
        guard let popupController else { return }
        if popupController.isVisible {
            popupController.hide()
            return
        }
        guard !isReadingSelection else { return }

        isReadingSelection = true
        SelectionReader.read { [weak self] text in
            guard let self else { return }
            self.isReadingSelection = false
            self.popupController?.show(sourceText: text)
        }
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func requestAccessibilityIfNeeded() {
        guard !SelectionReader.hasAccessibilityPermission else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}


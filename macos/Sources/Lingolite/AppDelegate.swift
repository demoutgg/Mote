import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var popupController: PopupController?
    private var settingsWindowController: SettingsWindowController?

    private let settingsStore = SettingsStore()
    private lazy var translationService = TranslationService(store: settingsStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityIfNeeded()
        setupStatusItem()

        popupController = PopupController(store: settingsStore, translationService: translationService)
        settingsWindowController = SettingsWindowController(store: settingsStore)

        hotKeyManager = HotKeyManager(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(optionKey)
        ) { [weak self] in
            self?.translateSelection()
        }
        hotKeyManager?.register()
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
        let selectedText = SelectionReader.selectedText() ?? ""
        popupController?.show(sourceText: selectedText, autoTranslate: !selectedText.isEmpty)
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
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}


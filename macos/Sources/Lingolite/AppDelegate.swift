// 应用入口：菜单栏、全局快捷键、权限引导；不含翻译业务逻辑。
import AppKit
import Carbon.HIToolbox
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyCenter: HotKeyCenter?
    private var popupController: PopupController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var cancellables = Set<AnyCancellable>()

    private let settingsStore = SettingsStore()
    private let translationService = TranslationService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        settingsStore.$config
            .map(\.statusIcon)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyStatusIcon()
            }
            .store(in: &cancellables)

        popupController = PopupController(store: settingsStore, service: translationService)
        settingsWindowController = SettingsWindowController(store: settingsStore)
        onboardingWindowController = OnboardingWindowController(
            store: settingsStore,
            onOpenSettings: { [weak self] in self?.settingsWindowController?.show() }
        )
        popupController?.onOpenSettings = { [weak self] in
            self?.settingsWindowController?.show()
        }

        let center = HotKeyCenter()
        hotKeyCenter = center
        let registered = [
            center.register(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey), id: 1) { [weak self] in
                self?.openManual()
            },
            center.register(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey), id: 2) { [weak self] in
                self?.translateSelection()
            },
            center.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey), id: 3) { [weak self] in
                self?.translateClipboard()
            },
        ]
        if registered.contains(false) {
            NSLog("Lingolite: failed to register one or more global hotkeys")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = "快捷键被占用"
                alert.informativeText = "⌥A / ⌥D / ⌥V 中有组合键已被其他应用注册。请退出冲突的应用（例如 Bob、MoePeek）后重新启动 Lingolite。"
                alert.addButton(withTitle: "知道了")
                alert.runModal()
            }
        }

        if !UserDefaults.standard.bool(forKey: OnboardingWindowController.completedKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.onboardingWindowController?.show()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        applyStatusIcon()

        let menu = NSMenu()
        menu.addItem(menuItem(title: "输入翻译", action: #selector(openManual), keyEquivalent: "a", modifiers: [.option]))
        menu.addItem(menuItem(title: "选中翻译（框选）", action: #selector(translateSelection), keyEquivalent: "d", modifiers: [.option]))
        menu.addItem(menuItem(title: "剪贴翻译", action: #selector(translateClipboard), keyEquivalent: "v", modifiers: [.option]))
        menu.addItem(menuItem(title: "使用指南…", action: #selector(showOnboarding)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "关于 Lingolite", action: #selector(showAbout)))
        menu.addItem(menuItem(title: "退出 Lingolite", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
    }

    private func applyStatusIcon() {
        guard let button = statusItem?.button else { return }
        let name = settingsStore.config.statusIcon
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            button.image = nil
            button.title = "译"
        } else if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Lingolite") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "译"
        }
        button.toolTip = "Lingolite · 选中文本按 ⌥D 翻译"
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(menuItem(title: "关于 Lingolite", action: #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "退出 Lingolite", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: NSSelectorFromString("cut:"), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: NSSelectorFromString("paste:"), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    @objc private func openManual() {
        guard let popupController else { return }
        if popupController.isVisible {
            popupController.hide()
            return
        }
        popupController.show(sourceText: "")
    }

    @objc private func translateSelection() {
        guard let popupController else { return }
        popupController.hide(restoreFocus: false)

        guard OCREngine.hasScreenPermission else {
            OCREngine.requestScreenPermission()
            popupController.showPlaceholder(
                message: "框选翻译需要“屏幕录制”权限。请在系统设置中授权；如果授权后仍提示，请重启 Lingolite 再试。"
            )
            return
        }

        OCREngine.captureAndRecognize { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(text):
                self.popupController?.show(sourceText: text)
            case let .failure(error):
                if let ocrError = error as? OCREngine.OCRError, case .cancelled = ocrError {
                    return
                }
                self.popupController?.showPlaceholder(message: error.localizedDescription)
            }
        }
    }

    @objc private func translateClipboard() {
        guard let popupController else { return }
        if popupController.isVisible {
            popupController.hide()
            return
        }
        if let text = clipboardText() {
            popupController.show(sourceText: text)
        } else {
            popupController.showPlaceholder(message: "剪贴板里没有可翻译的文本。")
        }
    }

    private func clipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    @objc private func showOnboarding() {
        onboardingWindowController?.show()
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Lingolite",
            .applicationVersion: version,
            .credits: NSAttributedString(
                string: "轻量、原生的 AI 划词翻译工具\n选中文本，按 ⌥L 即可翻译。",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
        AppActivation.activate(NSApp)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}


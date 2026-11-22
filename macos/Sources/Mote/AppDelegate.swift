// 应用入口：菜单栏、全局快捷键、权限引导；不含翻译业务逻辑。
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyCenter: HotKeyCenter?
    private var popupController: PopupController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var isReadingSelection = false

    private let settingsStore = SettingsStore()
    private let translationService = TranslationService()
    private let historyStore = HistoryStore()
    private let toastController = ToastController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.migrateLegacyIfNeeded()
        setupMainMenu()
        setupStatusItem()
        settingsStore.$config
            .map(\.statusIcon)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyStatusIcon()
            }
            .store(in: &cancellables)

        popupController = PopupController(
            store: settingsStore,
            service: translationService,
            history: historyStore
        )
        settingsWindowController = SettingsWindowController(
            store: settingsStore,
            history: historyStore
        )
        historyWindowController = HistoryWindowController(store: historyStore)
        settingsWindowController?.onStatusIconPreview = { [weak self] name in
            self?.applyStatusIcon(name)
        }
        popupController?.onOpenSettings = { [weak self] in
            self?.settingsWindowController?.show()
        }
        popupController?.onOpenHistory = { [weak self] in
            self?.openHistory()
        }

        let center = HotKeyCenter()
        hotKeyCenter = center
        registerHotKeys()
        settingsStore.$config
            .map(\.keyBindings)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.registerHotKeys()
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        promptPermissionsIfNeeded()
        handlePreviewArgument()
    }

    /// 启动后仍缺权限时提示一次（24 小时内不重复）；否则用户只有按到快捷键才会见到引导
    private func promptPermissionsIfNeeded() {
        let missing = !SelectionReader.hasAccessibilityPermission || !OCREngine.hasScreenPermission
        guard missing else { return }

        let key = "lastPermissionPromptAt"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            PermissionGuideController.shared.show()
        }
    }

    /// 开发用：带 `--preview=settings|history|permission|popup` 启动时直接开对应窗口，便于截图核对样式
    private func handlePreviewArgument() {
        let prefix = "--preview="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return
        }
        let target = String(argument.dropFirst(prefix.count))
        // settings:0…3 指定分页
        let parts = target.split(separator: ":")
        let paneIndex = parts.count > 1 ? Int(parts[1]) : nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if let paneIndex {
                self?.settingsWindowController?.show(pane: paneIndex)
                return
            }
            switch target {
            case "settings":
                self?.settingsWindowController?.show()
            case "history":
                self?.historyWindowController?.show()
            case "permission":
                PermissionGuideController.shared.show()
            case "selection":
                self?.translateSelection()
            case "screenshot":
                self?.captureAndTranslate()
            case "popup":
                self?.popupController?.show(sourceText: "Translation should feel instant. Mote keeps the window small, the shortcuts out of the way, and the result in your clipboard when you want it.")
            default:
                break
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        applyStatusIcon()
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        for action in ShortcutAction.allCases {
            let binding = settingsStore.config.binding(for: action)
            let actionItem = menuItem(
                title: action.title,
                action: #selector(performMenuItem(_:)),
                keyEquivalent: binding.keyEquivalent,
                modifiers: binding.eventModifiers
            )
            // 用 representedObject 带回动作，菜单与快捷键共用同一个 perform(_:)
            actionItem.representedObject = action.rawValue
            menu.addItem(actionItem)
        }
        menu.addItem(menuItem(title: "历史记录…", action: #selector(openHistory), keyEquivalent: "y"))
        menu.addItem(.separator())
        // 状态栏菜单弹出时应用未激活，菜单项的 ⌘ 快捷键不会生效，只留标题
        menu.addItem(menuItem(title: "设置", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "关于 Mote", action: #selector(showAbout)))
        menu.addItem(menuItem(title: "退出 Mote", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func performMenuItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = ShortcutAction(rawValue: raw) else { return }
        perform(action)
    }

    private func registerHotKeys() {
        guard let center = hotKeyCenter else { return }
        center.unregisterAll()

        var failures: [ShortcutAction] = []
        for action in ShortcutAction.allCases {
            let binding = settingsStore.config.binding(for: action)
            let registered = center.register(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                id: action.hotKeyID
            ) { [weak self] in
                self?.perform(action)
            }
            if !registered {
                failures.append(action)
            }
        }

        guard !failures.isEmpty else { return }
        let list = failures
            .map { "\($0.title)（\(settingsStore.config.binding(for: $0).display)）" }
            .joined(separator: "、")
        NSLog("Mote: hotkey registration failed for \(list)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let alert = NSAlert()
            alert.messageText = "快捷键被占用"
            alert.informativeText = "\(list) 已被其他应用注册。请在设置中改成其他组合，或关闭占用该快捷键的应用。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .input:
            openManual()
        case .selection:
            translateSelection()
        case .clipboard:
            translateClipboard()
        case .screenshot:
            captureAndTranslate()
        case .screenshotOCR:
            captureOCR()
        }
    }

    private func applyStatusIcon(_ override: String? = nil) {
        guard let button = statusItem?.button else { return }
        let name = (override ?? settingsStore.config.statusIcon)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            button.image = nil
            button.title = "译"
        } else if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Mote") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "译"
        }
        let selection = settingsStore.config.binding(for: .selection).display
        button.toolTip = "Mote · 选中文本按 \(selection) 翻译"
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(menuItem(title: "关于 Mote", action: #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(menuItem(title: "历史记录…", action: #selector(openHistory), keyEquivalent: "y"))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "退出 Mote", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let historyMenuItem = NSMenuItem()
        mainMenu.addItem(historyMenuItem)
        let historyMenu = NSMenu(title: "历史")
        // ⌘Y 已绑在上面的「历史记录…」，这里不再重复绑定
        historyMenu.addItem(menuItem(title: "显示历史记录", action: #selector(openHistory)))
        historyMenu.addItem(menuItem(title: "清空历史记录…", action: #selector(clearHistory)))
        historyMenuItem.submenu = historyMenu

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
            item.keyEquivalentModifierMask = modifiers.isEmpty ? [.command] : modifiers
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
        if popupController.isVisible {
            popupController.hide()
            return
        }
        guard !isReadingSelection else { return }

        guard SelectionReader.hasAccessibilityPermission else {
            PermissionGuideController.shared.show()
            return
        }

        isReadingSelection = true
        SelectionReader.read { [weak self] text in
            guard let self else { return }
            self.isReadingSelection = false
            // 读空就不弹窗：多数是没选中文本；若同时权限也没了（判定与读取之间有竞态），补一次引导
            guard !text.isEmpty else {
                if !SelectionReader.hasAccessibilityPermission {
                    PermissionGuideController.shared.show()
                }
                return
            }
            self.popupController?.show(sourceText: text)
        }
    }

    @objc private func captureAndTranslate() {
        popupController?.hide(restoreFocus: false)
        beginScreenshot { text in
            self.popupController?.show(sourceText: text)
        } onError: { message in
            self.popupController?.showPlaceholder(message: message)
        }
    }

    @objc private func captureOCR() {
        popupController?.hide(restoreFocus: false)
        beginScreenshot { [weak self] text in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            self.toastController.show("已复制 \(text.count) 个字符")
        } onError: { [weak self] message in
            self?.toastController.show(message)
        }
    }

    private func beginScreenshot(
        onText: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard OCREngine.hasScreenPermission else {
            PermissionGuideController.shared.show()
            return
        }

        OCREngine.captureInteractive { result in
            switch result {
            case let .success(text):
                onText(text)
            case let .failure(error):
                if let ocrError = error as? OCREngine.OCRError, case .cancelled = ocrError {
                    return
                }
                onError(error.localizedDescription)
            }
        }
    }

    @objc private func translateClipboard() {
        guard let popupController else { return }
        if popupController.isVisible {
            popupController.hide()
            return
        }
        // 剪贴板没有文本时什么都不做，和选中翻译一致：不弹空窗口
        guard let text = clipboardText() else { return }
        popupController.show(sourceText: text)
    }

    private func clipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    @objc private func openHistory() {
        historyWindowController?.show()
    }

    @objc private func clearHistory() {
        // 与历史页共用同一个确认 sheet，文案和行为保持一致
        historyWindowController?.confirmClear()
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Mote",
            .applicationVersion: version,
            .credits: NSAttributedString(
                string: "轻量、原生的 AI 翻译工具",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
        AppActivation.activate(NSApp)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}


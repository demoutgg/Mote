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
    private var historyWindowController: HistoryWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var isReadingSelection = false

    private let settingsStore = SettingsStore()
    private let translationService = TranslationService()
    private let historyStore = HistoryStore()
    private let toastController = ToastController()

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
        onboardingWindowController = OnboardingWindowController(
            store: settingsStore,
            onOpenSettings: { [weak self] in self?.settingsWindowController?.show() }
        )
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
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        for action in ShortcutAction.allCases {
            let binding = settingsStore.config.binding(for: action)
            let title = action == .screenshotOCR ? "截图 OCR（复制）" : action.title
            menu.addItem(
                menuItem(
                    title: title,
                    action: selector(for: action),
                    keyEquivalent: binding.keyEquivalent,
                    modifiers: binding.eventModifiers
                )
            )
        }
        menu.addItem(menuItem(title: "使用指南…", action: #selector(showOnboarding)))
        menu.addItem(menuItem(title: "历史记录…", action: #selector(openHistory), keyEquivalent: "y"))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(menuItem(title: "辅助功能权限…", action: #selector(openAccessibilitySettings)))
        menu.addItem(menuItem(title: "屏幕录制权限…", action: #selector(openScreenRecordingSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "关于 Lingolite", action: #selector(showAbout)))
        menu.addItem(menuItem(title: "退出 Lingolite", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
    }

    private func selector(for action: ShortcutAction) -> Selector {
        switch action {
        case .input:
            return #selector(openManual)
        case .selection:
            return #selector(translateSelection)
        case .clipboard:
            return #selector(translateClipboard)
        case .screenshot:
            return #selector(captureAndTranslate)
        case .screenshotOCR:
            return #selector(captureOCR)
        }
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
        NSLog("Lingolite: hotkey registration failed for \(list)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let alert = NSAlert()
            alert.messageText = "快捷键被占用"
            alert.informativeText = "\(list) 已被其他应用注册。请在设置中改成其他组合，或退出冲突的应用（例如 Bob、MoePeek）。"
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
        } else if name == "sparkles" {
            button.image = Self.sparklesTemplateImage()
            button.title = ""
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

    private static func sparklesTemplateImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()

        fillStar(center: NSPoint(x: 11.4, y: 6.6), radius: 6.2, innerRadius: 1.0)
        fillStar(center: NSPoint(x: 5.4, y: 12.4), radius: 3.0, innerRadius: 0.55)
        fillStar(center: NSPoint(x: 9.4, y: 15.3), radius: 1.9, innerRadius: 0.4)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func fillStar(center: NSPoint, radius: CGFloat, innerRadius: CGFloat) {
        let path = NSBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4 - .pi / 2
            let r = index.isMultiple(of: 2) ? radius : innerRadius
            let point = NSPoint(
                x: center.x + cos(angle) * r,
                y: center.y + sin(angle) * r
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        path.fill()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(menuItem(title: "关于 Lingolite", action: #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(menuItem(title: "历史记录…", action: #selector(openHistory), keyEquivalent: "y"))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "退出 Lingolite", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let historyMenuItem = NSMenuItem()
        mainMenu.addItem(historyMenuItem)
        let historyMenu = NSMenu(title: "历史")
        historyMenu.addItem(menuItem(title: "显示历史记录", action: #selector(openHistory), keyEquivalent: "y"))
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

        if !SelectionReader.hasAccessibilityPermission {
            SelectionReader.requestAccessibilityPermission()
        }

        isReadingSelection = true
        SelectionReader.read { [weak self] text in
            guard let self else { return }
            self.isReadingSelection = false
            if text.isEmpty {
                if !SelectionReader.hasAccessibilityPermission {
                    self.popupController?.showPlaceholder(
                        message: "选中翻译需要“辅助功能”权限。请在系统设置中授权后重试 ⌥D。"
                    )
                } else {
                    self.popupController?.show(sourceText: "")
                }
            } else {
                self.popupController?.show(sourceText: text)
            }
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
            OCREngine.requestScreenPermission()
            onError("截图功能需要“屏幕录制”权限。请在系统设置中授权；如果授权后仍提示，请重启 Lingolite 再试。")
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

    @objc private func openHistory() {
        historyWindowController?.show()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空全部历史记录？"
        alert.informativeText = "此操作不可撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            historyStore.clear()
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
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
                string: "轻量、原生的 AI 翻译工具\n⌥D 选中翻译 · ⌥S 截图翻译 · ⇧⌥S 截图 OCR",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
        AppActivation.activate(NSApp)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}


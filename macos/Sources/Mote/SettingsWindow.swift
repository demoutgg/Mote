// 设置窗口（纯 AppKit）：分页编辑通用、服务、翻译与历史。
// 改动即时生效直接落盘，没有保存/取消；非法状态（无可用服务、快捷键重复）只提示不写入。
import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let history: HistoryStore
    private let service = TranslationService()
    private var window: NSWindow?
    /// 每次重建窗口自增，异步回调据此判断结果是否还属于当前这扇窗
    private var session = 0
    private var panes: [NSView] = []
    private let container = NSView()
    private var measuredContentHeight: CGFloat = 640

    private var draft = AppConfig()
    private var draftKey = ""
    private var draftBaiduKey = ""

    /// 顶部分页导航；索引同时决定 makePane 建哪一页，标题行显示的也是这里的 label
    private static let paneTabs: [(label: String, symbol: String)] = [
        ("通用", "gearshape"),
        ("服务", "cloud"),
        ("翻译", "character.bubble"),
        ("历史", "clock.arrow.circlepath"),
        ("关于", "info.circle"),
    ]
    private let titleLabel = NSTextField(labelWithString: "Mote 设置")
    private let tabBar = SettingsTabBar(items: SettingsWindowController.paneTabs.map {
        SettingsTabBar.Item(label: $0.label, symbol: $0.symbol)
    })
    // 非法状态的就近提示：各自贴在出问题的那张卡片里，没内容时整行收起
    private let baiduHint = HintRow()
    private let llmHint = HintRow()
    private let shortcutHint = HintRow()
    /// 快捷键被拒时的临时提示到期后回到常规检查
    private var hintResetWorkItem: DispatchWorkItem?
    /// 连续拖动（滑块、步进）时合并写入，避免每一帧都落盘
    private var pendingCommit: DispatchWorkItem?

    // 权限
    private var permissionBanner: NSView?

    // 通用
    private var recorders: [RecorderView] = []
    private var widthField: NSTextField!
    private var widthStepper: NSStepper!
    private var heightField: NSTextField!
    private var heightStepper: NSStepper!
    private var statusIconField: NSTextField!
    private var statusIconPopup: NSPopUpButton!
    private var statusIconItems: [String] = []

    // 服务
    private var baiduSwitch: NSSwitch!
    private var baiduAppIDField: NSTextField!
    private var baiduKeyField: NSSecureTextField!
    private var baiduDetailRows: [NSView] = []
    private var baiduResultLabel: NSTextField!
    private var baiduTestButton: NSButton!
    private var llmSwitch: NSSwitch!
    private var endpointField: NSTextField!
    private var presetPopup: NSPopUpButton!
    private var apiKeyField: NSSecureTextField!
    private var modelField: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var llmDetailRows: [NSView] = []
    private var llmResultLabel: NSTextField!
    private var llmTestButton: NSButton!
    private var fetchModelsButton: NSButton!

    // 翻译
    private var languagePopup: NSPopUpButton!
    private var autoCopySwitch: NSSwitch!
    private var temperatureSlider: NSSlider!
    private var temperatureValue: NSTextField!
    private var promptTextView: NSTextView!

    var onStatusIconPreview: ((String) -> Void)?

    init(store: SettingsStore, history: HistoryStore) {
        self.store = store
        self.history = history
        super.init()
    }

    /// 开发用：直接打开指定分页（0 通用 / 1 服务 / 2 翻译 / 3 历史 / 4 关于），便于截图核对样式
    func show(pane index: Int) {
        show()
        guard index >= 0, index < panes.count else { return }
        selectPane(index)
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            AppActivation.activate(window)
            return
        }

        draft = store.config
        draftKey = store.apiKey
        draftBaiduKey = store.baiduKey

        let window = DismissibleWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mote 设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        // 标题行和 Tab 行都自绘：内容延伸到标题栏，红绿灯仍是系统默认位置
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = makeContentView()
        window.center()
        self.window = window
        session += 1
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppActivation.activate(window)
        // 首次打开时 contentView 里的 selectPane 还没有 window 引用，统一在窗口就位后定高
        resizeWindow()
        refreshHints()
    }


    func windowWillClose(_ notification: Notification) {
        hintResetWorkItem?.cancel()
        hintResetWorkItem = nil
        // 关窗时正在编辑的输入框还没失焦，先结束编辑把最后一段文字提交掉
        window?.makeFirstResponder(nil)
        commit()
        (notification.object as? NSWindow)?.contentView = nil
        window = nil
        releaseViews()
        MemoryPressure.relieve()
        onStatusIconPreview?(store.config.statusIcon)
        AppActivation.restoreAccessoryPolicy()
    }

    /// 关闭时清空所有视图引用，避免 AppKit 控件常驻内存。
    private func releaseViews() {
        container.subviews.forEach { $0.removeFromSuperview() }
        panes = []
        clearFieldReferences()
    }

    /// 分页销毁时同步清掉指向其内部控件的引用，下次重建时重新赋值
    private func clearFieldReferences() {
        recorders = []
        widthField = nil
        widthStepper = nil
        heightField = nil
        heightStepper = nil
        statusIconField = nil
        statusIconPopup = nil
        statusIconItems = []
        baiduSwitch = nil
        baiduAppIDField = nil
        baiduKeyField = nil
        baiduDetailRows = []
        baiduResultLabel = nil
        baiduTestButton = nil
        llmSwitch = nil
        endpointField = nil
        presetPopup = nil
        apiKeyField = nil
        modelField = nil
        modelPopup = nil
        llmDetailRows = []
        llmResultLabel = nil
        llmTestButton = nil
        fetchModelsButton = nil
        languagePopup = nil
        autoCopySwitch = nil
        temperatureSlider = nil
        temperatureValue = nil
        promptTextView = nil
        permissionBanner = nil
    }

    // MARK: - 窗口骨架

    private func makeContentView() -> NSView {
        let content = NSView()
        content.wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        tabBar.onSelect = { [weak self] index in self?.selectPane(index) }
        content.addSubview(tabBar)

        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)

        NSLayoutConstraint.activate([
            // 标题与红绿灯同一水平线，Tab 行紧随其下
            titleLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: content.topAnchor, constant: 20),

            tabBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 38),
            tabBar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 56),

            container.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        panes = [
            makeGeneralPane(),
            makeServicesPane(),
            makeTranslationPane(),
            HistoryPane(store: history),
            makeAboutPane(),
        ]
        measuredContentHeight = Self.measureContentHeight(panes, width: Self.windowWidth)
        selectPane(0)
        return content
    }

    private func selectPane(_ index: Int) {
        guard index >= 0, index < panes.count else { return }
        // 切页会拆掉旧分页的视图，先把正在编辑的输入框结束掉，否则最后一段文字丢失
        if window?.firstResponder is NSText {
            window?.makeFirstResponder(nil)
        }
        panes.forEach { $0.removeFromSuperview() }
        let pane = panes[index]
        pane.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: container.topAnchor),
            pane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        titleLabel.stringValue = "Mote 设置 · \(Self.paneTabs[index].label)"
        tabBar.select(index)
        container.layoutSubtreeIfNeeded()
        resizeWindow()
        (pane as? FormPane)?.scrollToTop()
    }

    private static let windowWidth: CGFloat = 640
    /// 标题行 20 + Tab 行 38…94，都是分页容器之外的部分（没有底部按钮条）
    private static let chromeHeight: CGFloat = 38 + 56
    /// 统一高度取最高分页，但压到这个上限以内，超出的分页自己滚动
    private static let maxWindowHeight: CGFloat = 780

    /// 在离屏宿主里量各分页的自然高度：文字只有在真实宽度下换行才对，
    /// 量完取最高值，保证切换分页时窗口高度不变、内容又不被切
    private static func measureContentHeight(_ panes: [NSView], width: CGFloat) -> CGFloat {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        var result: CGFloat = 0
        for pane in panes {
            pane.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(pane)
            let constraints = [
                pane.topAnchor.constraint(equalTo: host.topAnchor),
                pane.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ]
            NSLayoutConstraint.activate(constraints)
            host.layoutSubtreeIfNeeded()
            if let form = pane as? FormPane {
                result = max(result, form.measuredContentHeight)
            } else {
                result = max(result, pane.fittingSize.height)
            }
            NSLayoutConstraint.deactivate(constraints)
            pane.removeFromSuperview()
        }
        return result
    }

    private func resizeWindow() {
        guard let window else { return }
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = min(measuredContentHeight + Self.chromeHeight, Self.maxWindowHeight, available - 60)
        guard abs(window.frame.height - height) > 1 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }

    // MARK: - 通用

    private enum ControlTag {
        static let popupWidth = 101
        static let popupHeight = 102
        static let temperature = 103
    }

    private func makeGeneralPane() -> NSView {
        let pane = FormPane()

        // 权限提醒只在缺权限时出现，全部授权后整张卡片收起
        let bannerButton = FormRow.button("去授权", target: self, action: #selector(openPermissionGuide))
        permissionBanner = pane.addCard([
            FormRow.make(
                title: "尚未获得系统权限",
                detail: "辅助功能用于读取选中文本，屏幕录制用于截图翻译；不授权时对应操作会先提示。",
                accessory: bannerButton
            ),
        ])

        pane.addTitle("启动")
        let launchSwitch = FormRow.switchButton(
            isOn: LaunchAtLogin.isEnabled,
            target: self,
            action: #selector(launchToggled(_:))
        )
        pane.addCard([
            FormRow.make(title: "开机自动启动", accessory: launchSwitch),
            FormRow.noteRow("登录时自动启动 Mote，下次登录生效；移动应用后需要重新勾选一次。"),
        ])

        pane.addTitle("快捷键")
        var shortcutRows: [NSView] = []
        for (index, action) in ShortcutAction.allCases.enumerated() {
            let recorder = RecorderView()
            recorder.binding = draft.binding(for: action)
            recorder.onChange = { [weak self] binding in
                guard let self else { return }
                self.draft.setBinding(binding, for: action)
                self.commit()
            }
            recorder.onReject = { [weak self] message in
                self?.flashShortcutHint(message)
            }
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 96).isActive = true
            recorder.heightAnchor.constraint(equalToConstant: 24).isActive = true
            recorders.append(recorder)

            let reset = NSButton(
                image: NSImage(
                    systemSymbolName: "arrow.counterclockwise",
                    accessibilityDescription: "恢复默认"
                )!,
                target: self,
                action: #selector(resetShortcut(_:))
            )
            reset.isBordered = false
            reset.tag = index
            reset.toolTip = "恢复默认"

            let accessory = NSStackView(views: [recorder, reset])
            accessory.orientation = .horizontal
            accessory.alignment = .centerY
            accessory.spacing = 8
            shortcutRows.append(
                FormRow.make(title: action.title, detail: action.detail, accessory: accessory)
            )
        }
        shortcutRows.append(
            FormRow.noteRow("选中翻译需要辅助功能权限；截图功能需要屏幕录制权限。快捷键被占用时，点一下右侧按键重新录制即可。")
        )
        shortcutRows.append(shortcutHint)
        pane.addCard(shortcutRows)

        pane.addTitle("弹窗")
        widthField = FormRow.valueField(
            "\(Int(draft.popupWidth))",
            width: 64,
            target: self,
            action: #selector(dimensionChanged(_:))
        )
        widthField.tag = ControlTag.popupWidth
        widthField.formatter = dimensionFormatter()
        widthStepper = dimensionStepper(value: draft.popupWidth, min: 460, max: 900, tag: ControlTag.popupWidth)
        heightField = FormRow.valueField(
            "\(Int(draft.popupHeight))",
            width: 64,
            target: self,
            action: #selector(dimensionChanged(_:))
        )
        heightField.tag = ControlTag.popupHeight
        heightField.formatter = dimensionFormatter()
        heightStepper = dimensionStepper(value: draft.popupHeight, min: 340, max: 800, tag: ControlTag.popupHeight)

        pane.addCard([
            dimensionRow(title: "宽度", field: widthField, stepper: widthStepper, unit: "pt（460–900）"),
            dimensionRow(title: "高度", field: heightField, stepper: heightStepper, unit: "pt（340–800）"),
            FormRow.noteRow("也可以在弹窗右下角拖动调整，位置会自动记住。"),
        ])

        // 菜单栏图标改动最直观，放在弹窗设置之后单独一节
        pane.addTitle("外观")
        statusIconPopup = FormRow.popup(width: 120)
        // 菜单项与 statusIconItems 一一对应：自定义符号追加一项，末项是「显示“译”字」（空字符串）
        var icons = AppConfig.statusIcons
        if !draft.statusIcon.isEmpty && !icons.contains(draft.statusIcon) {
            icons.append(draft.statusIcon)
        }
        icons.append("")
        statusIconItems = icons
        statusIconPopup.addItems(withTitles: icons.map { $0.isEmpty ? "显示“译”字" : statusName($0) })
        // 每一项都带图标预览，避免只能靠名字猜是哪个符号
        for (index, item) in statusIconPopup.itemArray.enumerated() where index < icons.count {
            item.image = statusIconMenuItemImage(for: icons[index])
        }
        statusIconPopup.selectItem(at: icons.firstIndex(of: draft.statusIcon) ?? icons.count - 1)
        statusIconPopup.target = self
        statusIconPopup.action = #selector(statusIconPicked(_:))

        statusIconField = FormRow.textField(width: 220)
        statusIconField.stringValue = draft.statusIcon
        statusIconField.placeholderString = "custom.icon.name"
        statusIconField.target = self
        statusIconField.action = #selector(statusIconTyped(_:))
        statusIconField.cell?.sendsActionOnEndEditing = true

        pane.addCard([
            FormRow.make(title: "菜单栏图标", accessory: statusIconPopup),
            FormRow.make(title: "自定义符号", accessory: statusIconField),
            FormRow.noteRow("留空显示“译”字；支持任意 SF Symbols 名称。"),
        ])

        updateIconPreview(draft.statusIcon)
        refreshPermissionBanner()
        return pane
    }

    private func makeAboutPane() -> NSView {
        let pane = FormPane()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? ""

        // 上半部照系统「关于」面板排：大图标、名称、版本、一句话定位，全部居中
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 88).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 88).isActive = true

        let name = NSTextField(labelWithString: "Mote")
        name.font = .systemFont(ofSize: 22, weight: .semibold)
        name.alignment = .center

        let versionLabel = NSTextField(labelWithString: "版本 \(version)（\(build)）")
        versionLabel.font = Theme.Font.footnote
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let tagline = NSTextField(labelWithString: "轻量、原生的 AI 翻译工具")
        tagline.font = Theme.Font.body
        tagline.alignment = .center

        let hero = NSStackView(views: [icon, name, versionLabel, tagline])
        hero.orientation = .vertical
        hero.alignment = .centerX
        hero.spacing = 6
        hero.setCustomSpacing(Theme.Spacing.l, after: icon)
        hero.edgeInsets = NSEdgeInsets(top: 28, left: 0, bottom: 24, right: 0)
        hero.translatesAutoresizingMaskIntoConstraints = false
        pane.addBlock(hero)

        pane.addTitle("链接")
        let link = NSButton(title: "github.com/demoutgg/Mote", target: self, action: #selector(openRepo))
        link.isBordered = false
        link.contentTintColor = .linkColor
        link.font = Theme.Font.footnote
        pane.addCard([
            linkRow(link),
            FormRow.noteRow("问题反馈与新版本都在这里。"),
        ])

        pane.addTitle("隐私")
        pane.addCard([
            FormRow.make(title: "翻译请求", detail: "直接发往你配置的服务商", accessory: valueText("本地直连")),
            FormRow.make(title: "数据收集", detail: "不收集遥测，历史记录只存在本机", accessory: valueText("无")),
        ])

        return pane
    }

    private func sliderRow(title: String, slider: NSSlider, value: NSTextField) -> NSView {
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let accessory = NSStackView(views: [slider, value])
        accessory.orientation = .horizontal
        accessory.alignment = .centerY
        accessory.spacing = 10
        return FormRow.make(title: title, accessory: accessory)
    }

    /// 尺寸行：输入框 + 步进，不依赖滑块条的长度表达数值
    private func dimensionRow(
        title: String,
        field: NSTextField,
        stepper: NSStepper,
        unit: String
    ) -> NSView {
        let unitLabel = NSTextField(labelWithString: unit)
        unitLabel.font = Theme.Font.footnote
        unitLabel.textColor = .secondaryLabelColor
        let accessory = NSStackView(views: [field, stepper, unitLabel])
        accessory.orientation = .horizontal
        accessory.alignment = .centerY
        accessory.spacing = Theme.Spacing.m
        return FormRow.make(title: title, accessory: accessory)
    }

    private func dimensionStepper(value: Double, min: Double, max: Double, tag: Int) -> NSStepper {
        let stepper = NSStepper()
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 10
        stepper.doubleValue = value
        stepper.valueWraps = false
        stepper.autorepeat = true
        stepper.tag = tag
        stepper.target = self
        stepper.action = #selector(dimensionChanged(_:))
        return stepper
    }

    private func dimensionFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 1000
        return formatter
    }

    private func linkRow(_ button: NSButton) -> NSView {
        let row = RowStack(views: [button])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 6, left: Theme.Spacing.l, bottom: 6, right: Theme.Spacing.l)
        return row
    }

    private func valueText(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.Font.footnote
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: - 服务

    private func makeServicesPane() -> NSView {
        let pane = FormPane()

        pane.addTitle("百度翻译")
        baiduSwitch = FormRow.switchButton(
            isOn: draft.baiduEnabled,
            target: self,
            action: #selector(baiduToggled(_:))
        )
        baiduAppIDField = FormRow.textField()
        baiduAppIDField.stringValue = draft.baiduAppID
        baiduAppIDField.delegate = self
        baiduKeyField = FormRow.secureField()
        baiduKeyField.stringValue = draftBaiduKey
        baiduKeyField.delegate = self
        baiduResultLabel = statusLabel()
        baiduTestButton = FormRow.button("测试百度翻译", target: self, action: #selector(testBaidu))

        let baiduTestRow = testRow(baiduResultLabel, button: baiduTestButton)
        let baiduLink = NSButton(title: "打开百度翻译开放平台", target: self, action: #selector(openBaidu))
        baiduLink.isBordered = false
        baiduLink.contentTintColor = .linkColor
        baiduLink.font = Theme.Font.footnote
        let baiduRows = [
            FormRow.make(title: "启用百度翻译", accessory: baiduSwitch),
            FormRow.make(title: "AppID", accessory: baiduAppIDField),
            FormRow.make(title: "密钥", accessory: baiduKeyField),
            baiduTestRow,
            linkRow(baiduLink),
            FormRow.noteRow("密钥只保存在本机，不会上传。"),
            baiduHint,
        ]
        // 提示行不跟着服务开关置灰，开关关掉时它才需要显示
        baiduDetailRows = baiduRows.dropFirst().filter { $0 !== baiduHint }
        pane.addCard(baiduRows)

        pane.addTitle("AI 翻译（OpenAI 兼容）")
        llmSwitch = FormRow.switchButton(
            isOn: draft.llmEnabled,
            target: self,
            action: #selector(llmToggled(_:))
        )
        // 三个输入框统一 240：接口地址放得下长 base_url，API Key 与模型也同宽
        endpointField = FormRow.textField(width: 240)
        endpointField.stringValue = draft.endpoint
        endpointField.delegate = self
        presetPopup = FormRow.popup(width: 96)
        presetPopup.addItems(withTitles: ServicePreset.allCases.map(\.rawValue))
        presetPopup.addItem(withTitle: "自定义")
        presetPopup.selectItem(
            withTitle: ServicePreset.detect(draft.endpoint)?.rawValue ?? "自定义"
        )
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))

        apiKeyField = FormRow.secureField(width: 240)
        apiKeyField.stringValue = draftKey
        apiKeyField.delegate = self
        // 模型名普遍偏长（如 workbuddy/hy4flash-free），窄输入框会被截断得看不出全名
        modelField = FormRow.textField(width: 240)
        modelField.stringValue = draft.model
        modelField.delegate = self
        fetchModelsButton = FormRow.button("获取模型", target: self, action: #selector(fetchModels))
        modelPopup = FormRow.popup(width: 90)
        modelPopup.isHidden = true
        modelPopup.target = self
        modelPopup.action = #selector(modelPicked(_:))
        llmResultLabel = statusLabel()
        llmTestButton = FormRow.button("测试连接", target: self, action: #selector(testLLM))

        // 拉取按钮与结果下拉占同一个位置：拉取成功后互换，避免挤占输入框宽度
        let modelSlot = NSStackView(views: [fetchModelsButton, modelPopup])
        modelSlot.orientation = .horizontal
        modelSlot.alignment = .centerY
        modelSlot.spacing = Theme.Spacing.s
        modelSlot.translatesAutoresizingMaskIntoConstraints = false

        let endpointRow = FormRow.make(
            title: "接口地址",
            accessory: FormRow.group(endpointField, control: presetPopup)
        )
        let modelRow = FormRow.make(
            title: "模型",
            accessory: FormRow.group(modelField, control: modelSlot)
        )
        let llmTestRow = testRow(llmResultLabel, button: llmTestButton)
        let llmRows = [
            FormRow.make(title: "启用 AI 翻译", accessory: llmSwitch),
            endpointRow,
            FormRow.make(title: "API Key", accessory: apiKeyField),
            modelRow,
            llmTestRow,
            FormRow.noteRow("API Key 只保存在本机，不会上传。"),
            llmHint,
        ]
        llmDetailRows = llmRows.dropFirst().filter { $0 !== llmHint }
        pane.addCard(llmRows)

        setDetails(baiduDetailRows, enabled: draft.baiduEnabled)
        setDetails(llmDetailRows, enabled: draft.llmEnabled)
        return pane
    }

    private enum ServicePreset: String, CaseIterable {
        case openAI = "OpenAI"
        case deepSeek = "DeepSeek"
        case ollama = "Ollama（本地）"
        case lmStudio = "LM Studio（本地）"

        var endpoint: String {
            switch self {
            case .openAI: return "https://api.openai.com/v1"
            case .deepSeek: return "https://api.deepseek.com/v1"
            case .ollama: return "http://127.0.0.1:11434/v1"
            case .lmStudio: return "http://127.0.0.1:1234/v1"
            }
        }

        var model: String {
            switch self {
            case .openAI: return "gpt-4o-mini"
            case .deepSeek: return "deepseek-chat"
            case .ollama: return "qwen2.5:7b"
            case .lmStudio: return "local-model"
            }
        }

        static func detect(_ endpoint: String) -> ServicePreset? {
            let lower = endpoint.lowercased()
            if lower.contains("api.openai.com") { return .openAI }
            if lower.contains("api.deepseek.com") { return .deepSeek }
            if lower.contains("11434") { return .ollama }
            if lower.contains("1234") { return .lmStudio }
            return nil
        }
    }

    // MARK: - 翻译

    private func makeTranslationPane() -> NSView {
        let pane = FormPane()

        pane.addTitle("语言")
        languagePopup = FormRow.popup(width: 200)
        languagePopup.addItems(withTitles: AppConfig.targetLanguages)
        languagePopup.selectItem(withTitle: draft.targetLanguage)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        autoCopySwitch = FormRow.switchButton(
            isOn: draft.autoCopy,
            target: self,
            action: #selector(autoCopyToggled(_:))
        )
        pane.addCard([
            FormRow.make(title: "目标语言", accessory: languagePopup),
            FormRow.make(title: "翻译完成后自动复制译文", accessory: autoCopySwitch),
        ])

        pane.addTitle("AI 参数")
        temperatureSlider = NSSlider(value: draft.temperature, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged(_:)))
        temperatureSlider.tag = ControlTag.temperature
        temperatureValue = FormRow.valueField(
            String(format: "%.2f", draft.temperature),
            target: self,
            action: #selector(temperatureFieldChanged(_:))
        )
        temperatureValue.formatter = temperatureFormatter()
        pane.addCard([sliderRow(title: "随机性", slider: temperatureSlider, value: temperatureValue)])

        let toggleRow = FormRow.make(
            title: "系统提示词",
            detail: "发给模型的 system 内容，可自行调整"
        )

        promptTextView = NSTextView()
        promptTextView.font = Theme.Font.mono
        promptTextView.isRichText = false
        promptTextView.autoresizingMask = [.width]
        promptTextView.textContainerInset = NSSize(width: 6, height: 6)
        promptTextView.textContainer?.widthTracksTextView = true
        promptTextView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        promptTextView.string = draft.systemPrompt
        promptTextView.delegate = self

        let promptScroll = SmoothScrollView()
        promptScroll.documentView = promptTextView
        promptScroll.hasVerticalScroller = true
        promptScroll.scrollerStyle = .overlay
        promptScroll.autohidesScrollers = true
        promptScroll.borderType = .bezelBorder
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.heightAnchor.constraint(equalToConstant: 180).isActive = true

        let resetPrompt = FormRow.button("恢复默认", target: self, action: #selector(resetPrompt))
        let resetRow = NSStackView(views: [
            valueText("使用 {targetLang} 表示目标语言。"),
            NSView(),
            resetPrompt,
        ])
        resetRow.orientation = .horizontal
        resetRow.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 8, right: 14)

        let promptBody = NSStackView(views: [promptScroll])
        promptBody.orientation = .vertical
        promptBody.alignment = .leading
        promptBody.spacing = 0
        promptBody.edgeInsets = NSEdgeInsets(top: 2, left: 16, bottom: 8, right: 16)
        promptBody.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.widthAnchor.constraint(equalTo: promptBody.widthAnchor, constant: -32).isActive = true

        pane.addCard([toggleRow, promptBody, resetRow])

        return pane
    }

    // MARK: - 动作

    @objc private func launchToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            sender.state = LaunchAtLogin.isEnabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "无法设置开机自启"
            alert.informativeText = error.localizedDescription
            if let window {
                alert.beginSheetModal(for: window)
            }
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        switch sender.tag {
        case ControlTag.temperature:
            draft.temperature = sender.doubleValue
            temperatureValue.stringValue = String(format: "%.2f", sender.doubleValue)
            commitSoon()
        default:
            break
        }
    }

    /// 弹窗宽高：输入框与步进共用同一个入口，越界按边界取值
    @objc private func dimensionChanged(_ sender: NSControl) {
        let isWidth = sender.tag == ControlTag.popupWidth
        let lower: Double = isWidth ? 460 : 340
        let upper: Double = isWidth ? 900 : 800
        let value = min(max(sender.doubleValue.rounded(), lower), upper)

        if isWidth {
            draft.popupWidth = value
            widthField.stringValue = "\(Int(value))"
            widthStepper.doubleValue = value
        } else {
            draft.popupHeight = value
            heightField.stringValue = "\(Int(value))"
            heightStepper.doubleValue = value
        }
        commitSoon()
    }

    /// 直接键入随机性：与滑块双向同步，超范围按边界取值
    @objc private func temperatureFieldChanged(_ sender: NSTextField) {
        let value = min(max(sender.doubleValue, 0), 1)
        draft.temperature = value
        temperatureSlider.doubleValue = value
        sender.stringValue = String(format: "%.2f", value)
        commit()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        draft.targetLanguage = sender.titleOfSelectedItem ?? draft.targetLanguage
        commit()
    }

    private func temperatureFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimum = 0
        formatter.maximum = 1
        return formatter
    }

    @objc private func resetShortcut(_ sender: NSButton) {
        let actions = ShortcutAction.allCases
        guard sender.tag >= 0, sender.tag < actions.count else { return }
        let action = actions[sender.tag]
        draft.resetBinding(for: action)
        recorders[sender.tag].binding = draft.binding(for: action)
        recorders[sender.tag].needsDisplay = true
        commit()
    }

    @objc private func statusIconPicked(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < statusIconItems.count else { return }
        let icon = statusIconItems[index]
        draft.statusIcon = icon
        statusIconField.stringValue = icon
        updateIconPreview(icon)
        commit()
    }

    @objc private func statusIconTyped(_ sender: NSTextField) {
        draft.statusIcon = sender.stringValue.trimmingCharacters(in: .whitespaces)
        updateIconPreview(draft.statusIcon)
        commit()
    }

    /// 下拉按钮本身已显示所选图标，这里只通知外部同步状态栏预览
    private func updateIconPreview(_ icon: String) {
        onStatusIconPreview?(icon)
    }

    /// 下拉列表里的图标预览；空字符串代表「显示“译”字」那一项。
    private func statusIconMenuItemImage(for icon: String) -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        guard !icon.isEmpty else {
            let image = NSImage(size: size, flipped: false) { rect in
                let text = "译" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                ]
                let textSize = text.size(withAttributes: attributes)
                text.draw(
                    at: NSPoint(
                        x: rect.midX - textSize.width / 2,
                        y: rect.midY - textSize.height / 2
                    ),
                    withAttributes: attributes
                )
                return true
            }
            image.isTemplate = true
            return image
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func statusName(_ icon: String) -> String {
        switch icon {
        case "sparkles": return "星光（双星）"
        case "sparkle": return "星光（单星）"
        default: return icon
        }
    }

    @objc private func baiduToggled(_ sender: NSSwitch) {
        draft.baiduEnabled = sender.state == .on
        setDetails(baiduDetailRows, enabled: draft.baiduEnabled)
        commit()
    }

    @objc private func llmToggled(_ sender: NSSwitch) {
        draft.llmEnabled = sender.state == .on
        setDetails(llmDetailRows, enabled: draft.llmEnabled)
        commit()
    }

    private func setDetails(_ rows: [NSView], enabled: Bool) {
        rows.forEach { setEnabled($0, enabled) }
    }

    private func setEnabled(_ view: NSView, _ enabled: Bool) {
        if let control = view as? NSControl {
            control.isEnabled = enabled
        }
        view.subviews.forEach { setEnabled($0, enabled) }
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem ?? ""
        guard let preset = ServicePreset(rawValue: title) else { return }
        endpointField.stringValue = preset.endpoint
        modelField.stringValue = preset.model
        resetModelPicker()
        commit()
    }

    /// 接口地址一变，之前拉到的模型列表就不作数了，换回「获取模型」按钮
    private func resetModelPicker() {
        modelPopup?.isHidden = true
        fetchModelsButton?.isHidden = false
    }

    @objc private func modelPicked(_ sender: NSPopUpButton) {
        // 第 0 项是「可选 N 个」占位，选中它不能当模型名写进输入框
        guard sender.indexOfSelectedItem > 0, let title = sender.titleOfSelectedItem else { return }
        modelField.stringValue = title
        commit()
    }

    @objc private func autoCopyToggled(_ sender: NSSwitch) {
        draft.autoCopy = sender.state == .on
        commit()
    }

    @objc private func resetPrompt() {
        promptTextView.string = AppConfig.defaultPrompt
        commit()
    }

    @objc private func openRepo() {
        NSWorkspace.shared.open(URL(string: "https://github.com/demoutgg/Mote")!)
    }

    @objc private func openBaidu() {
        NSWorkspace.shared.open(URL(string: "https://fanyi-api.baidu.com/")!)
    }

    /// 测试结果贴着「连接测试」按钮左侧显示：不额外占行，卡片高度不变，行不会跳动。
    /// 太长时截断，完整内容放 toolTip。
    private func statusLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = Theme.Font.footnote
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        return label
    }

    private func testRow(_ label: NSTextField, button: NSButton) -> NSView {
        let group = NSStackView(views: [label, button])
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = Theme.Spacing.s
        group.translatesAutoresizingMaskIntoConstraints = false
        return FormRow.make(title: "连接测试", accessory: group)
    }

    @objc private func testLLM() {
        let config = collectConfig()
        let key = apiKeyField.stringValue
        llmTestButton.isEnabled = false
        llmResultLabel.isHidden = false
        llmResultLabel.stringValue = "测试中…"
        llmResultLabel.textColor = .secondaryLabelColor
        llmResultLabel.toolTip = nil
        let service = self.service
        let session = self.session
        Task { @MainActor [weak self] in
            let start = Date()
            var message = ""
            var detail: String?
            var color = NSColor.secondaryLabelColor
            do {
                let output = try await service.translate(
                    text: "Hello",
                    config: config,
                    apiKey: key
                ) { _ in }
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                message = "连接成功 · \(ms) ms"
                detail = "返回：\(output.prefix(120))"
                color = .systemGreen
            } catch {
                message = error.localizedDescription
                detail = error.localizedDescription
                color = .systemRed
            }
            // 关窗后控件被 releaseViews() 置空、重开又是新窗口，session 与可选绑定都要过
            guard let self, self.window != nil, self.session == session,
                  let label = self.llmResultLabel,
                  let button = self.llmTestButton else { return }
            label.stringValue = message
            label.textColor = color
            label.toolTip = detail
            button.isEnabled = true
        }
    }

    @objc private func testBaidu() {
        let config = collectConfig()
        let secret = baiduKeyField.stringValue
        baiduTestButton.isEnabled = false
        baiduResultLabel.isHidden = false
        baiduResultLabel.stringValue = "测试中…"
        baiduResultLabel.textColor = .secondaryLabelColor
        baiduResultLabel.toolTip = nil
        let service = self.service
        let session = self.session
        Task { @MainActor [weak self] in
            let start = Date()
            var message = ""
            var detail: String?
            var color = NSColor.secondaryLabelColor
            do {
                let output = try await service.translateBaidu(
                    text: "Hello",
                    config: config,
                    secret: secret
                )
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                message = "连接成功 · \(ms) ms"
                detail = "返回：\(output.prefix(120))"
                color = .systemGreen
            } catch {
                message = error.localizedDescription
                detail = error.localizedDescription
                color = .systemRed
            }
            guard let self, self.window != nil, self.session == session,
                  let label = self.baiduResultLabel,
                  let button = self.baiduTestButton else { return }
            label.stringValue = message
            label.textColor = color
            label.toolTip = detail
            button.isEnabled = true
        }
    }

    @objc private func fetchModels() {
        let config = collectConfig()
        let key = apiKeyField.stringValue
        fetchModelsButton.isEnabled = false
        let service = self.service
        let session = self.session
        Task { @MainActor [weak self] in
            var models: [String] = []
            var failure: String?
            do {
                models = try await service.fetchModels(config: config, apiKey: key)
            } catch {
                failure = error.localizedDescription
            }
            // 关窗后控件被 releaseViews() 置空、重开又是新窗口，session 与可选绑定都要过
            guard let self, self.window != nil, self.session == session,
                  let button = self.fetchModelsButton,
                  let label = self.llmResultLabel,
                  let popup = self.modelPopup else { return }
            button.isEnabled = true
            if let failure {
                label.isHidden = false
                label.stringValue = failure
                label.textColor = .systemRed
                return
            }
            if !config.model.isEmpty && !models.contains(config.model) {
                models.insert(config.model, at: 0)
            }
            popup.removeAllItems()
            popup.addItem(withTitle: "可选 \(models.count) 个")
            popup.addItems(withTitles: models)
            popup.isHidden = false
            button.isHidden = true
        }
    }

    // MARK: - 即时生效

    private func collectConfig() -> AppConfig {
        var config = draft
        config.endpoint = endpointField?.stringValue ?? draft.endpoint
        config.model = modelField?.stringValue ?? draft.model
        config.baiduAppID = baiduAppIDField?.stringValue ?? draft.baiduAppID
        config.temperature = temperatureSlider?.doubleValue ?? draft.temperature
        config.systemPrompt = promptTextView?.string ?? draft.systemPrompt
        // 分页可能没建（按需构建），没建时沿用 draft，不能当成「关」
        config.llmEnabled = llmSwitch.map { $0.state == .on } ?? draft.llmEnabled
        config.baiduEnabled = baiduSwitch.map { $0.state == .on } ?? draft.baiduEnabled
        config.autoCopy = autoCopySwitch.map { $0.state == .on } ?? draft.autoCopy
        config.targetLanguage =
            languagePopup?.titleOfSelectedItem ?? draft.targetLanguage
        config.statusIcon = statusIconField?.stringValue ?? draft.statusIcon
        config.popupWidth = widthField?.doubleValue ?? draft.popupWidth
        config.popupHeight = heightField?.doubleValue ?? draft.popupHeight
        return config
    }

    /// 即时生效入口：任何控件改完就落到 config.json 与密钥文件。
    /// 非法状态只提示不写入——存下去也是一个翻译必定失败的配置。
    private func commit() {
        pendingCommit?.cancel()
        pendingCommit = nil

        let config = collectConfig()
        let noService = !config.llmEnabled && !config.baiduEnabled
        let missingLLM = config.llmEnabled && (
            config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        baiduHint.text = noService ? "至少启用一个翻译服务" : ""
        llmHint.text = missingLLM ? "启用 AI 服务需要填写接口地址与模型" : ""
        // 快捷键被拒的临时提示还在显示时不要被覆盖
        if hintResetWorkItem == nil {
            shortcutHint.text = shortcutConflict ? "存在重复快捷键" : ""
        }
        guard !noService, !missingLLM, !shortcutConflict else { return }

        let key = (apiKeyField?.stringValue ?? draftKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baiduKey = (baiduKeyField?.stringValue ?? draftBaiduKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 没变化就不碰磁盘，尤其是密钥文件
        guard config != draft || key != draftKey || baiduKey != draftBaiduKey else { return }

        store.config = config
        store.apiKey = key
        store.baiduKey = baiduKey
        store.save()
        // save() 会把字段 trim 并夹到合法区间，回读一遍让内存里的值和磁盘一致
        draft = store.config
        draftKey = store.apiKey
        draftBaiduKey = store.baiduKey
        onStatusIconPreview?(store.config.statusIcon)
    }

    /// 滑块拖拽、步进连点会连着触发，合并成一次写入
    private func commitSoon() {
        pendingCommit?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.commit() }
        pendingCommit = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    /// 打开窗口时按已保存的值算一次提示，之后由 commit 维护
    private func refreshHints() {
        let missingLLM = draft.llmEnabled && (
            draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        baiduHint.text = draft.llmEnabled || draft.baiduEnabled ? "" : "至少启用一个翻译服务"
        llmHint.text = missingLLM ? "启用 AI 服务需要填写接口地址与模型" : ""
        shortcutHint.text = shortcutConflict ? "存在重复快捷键" : ""
    }

    /// 录制快捷键被占用时的临时提示，2.4s 后回到冲突检查
    private func flashShortcutHint(_ message: String) {
        hintResetWorkItem?.cancel()
        shortcutHint.text = message
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hintResetWorkItem = nil
            self.shortcutHint.text = self.shortcutConflict ? "存在重复快捷键" : ""
        }
        hintResetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: item)
    }

    @objc private func openPermissionGuide() {
        // 和授权引导窗走同一条流程：登记系统权限、打开设置、贴浮条、轮询到授权自动收
        PermissionGuideController.shared.show()
    }

    /// 两项权限都拿到后，顶部提醒整条收起
    private func refreshPermissionBanner() {
        permissionBanner?.isHidden = PermissionKind.allCases.allSatisfy(\.isGranted)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshPermissionBanner()
    }

    private var shortcutConflict: Bool {
        let signatures = ShortcutAction.allCases.map { action -> String in
            let binding = draft.binding(for: action)
            return "\(binding.keyCode)-\(binding.modifiers)"
        }
        return Set(signatures).count != signatures.count
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    /// 接口地址与模型是自由输入：打字时只刷新提示，落盘等失焦
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === endpointField || field === modelField else { return }
        if field === endpointField { resetModelPicker() }
        let endpoint = (endpointField?.stringValue ?? draft.endpoint)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (modelField?.stringValue ?? draft.model)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        llmHint.text = draft.llmEnabled && (endpoint.isEmpty || model.isEmpty)
            ? "启用 AI 服务需要填写接口地址与模型"
            : ""
    }

    /// 失焦即提交，不需要再点保存
    func controlTextDidEndEditing(_ notification: Notification) {
        commit()
    }
}

extension SettingsWindowController: NSTextViewDelegate {
    /// 系统提示词同理，编辑结束才写盘
    func textDidEndEditing(_ notification: Notification) {
        commit()
    }
}

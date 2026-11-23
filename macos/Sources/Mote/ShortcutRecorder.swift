// 快捷键录制控件：点击后按下组合键，Esc 取消；只负责键盘录入与样式，不写配置。
import AppKit

final class RecorderView: NSView {
    var binding = ShortcutAction.input.defaultBinding {
        didSet { refreshLabel() }
    }

    var onChange: ((KeyBinding) -> Void)?
    /// 组合键被拒时的提示文案，交给调用方显示
    var onReject: ((String) -> Void)?

    private var isRecording = false
    private let titleLabel = NSTextField(labelWithString: "")

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 24) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installLabelIfNeeded()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installLabelIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
        installLabelIfNeeded()

        // 和卡片一样不描边：靠填充色差表示这里是可点的输入位
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: Theme.Radius.small,
            yRadius: Theme.Radius.small
        )
        (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.14)
            : Theme.wellFill
        ).setFill()
        path.fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        refreshLabel()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshLabel()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            refreshLabel()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonModifiers = KeyBinding.carbonModifiers(from: flags)
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }

        if let reason = Self.rejectionReason(for: event) {
            NSSound.beep()
            onReject?(reason)
            return
        }

        let newBinding = KeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers,
            display: KeyBinding.displayString(flags: flags, event: event),
            keyEquivalent: event.charactersIgnoringModifiers?.lowercased() ?? ""
        )
        isRecording = false
        binding = newBinding
        onChange?(newBinding)
        refreshLabel()
    }

    /// 背景用 draw 画，文字交给 NSTextField：手写 NSString.draw 在翻转坐标里会画成倒的
    private func installLabelIfNeeded() {
        guard titleLabel.superview == nil else { return }
        titleLabel.font = Theme.Font.mono
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
        ])
        refreshLabel()
    }

    private func refreshLabel() {
        installLabelIfNeeded()
        titleLabel.stringValue = isRecording ? "按下快捷键…" : binding.display
        titleLabel.textColor = isRecording ? .controlAccentColor : .labelColor
        needsDisplay = true
    }

    /// 只拦「⌘ / ⇧⌘」这类必然被系统或前台应用占用的组合；带 ⌥ ⌃ 的组合基本不冲突
    private static func rejectionReason(for event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.option), !flags.contains(.control) else { return nil }

        // Q W H M ` Tab Space 与 ⇧⌘3/4/5/6 截图
        let reserved: Set<UInt16> = [12, 13, 4, 46, 50, 48, 49, 20, 21, 23, 22]
        guard reserved.contains(event.keyCode) else { return nil }
        return "⌘Q、⌘W、⌘Tab 等系统快捷键不能用作全局快捷键，建议加上 ⌥"
    }
}

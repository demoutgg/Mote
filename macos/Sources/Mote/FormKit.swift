// 设置界面通用组件：卡片分区、表单行和滚动容器；不涉及配置读写。
import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 设置卡片容器：只靠填充色分层，不用描边；底色跟随深浅色外观重设
final class CardView: NSStackView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        wantsLayer = true
        layer?.cornerRadius = Theme.Radius.card
        layer?.backgroundColor = Theme.cardFill.cgColor
    }

    /// 切深浅色时 updateLayer 不一定被调用，这里显式标脏
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 卡片内的一行：可选在顶部画 1pt 分隔线。
/// 画在行自身而不是插在行之间，折叠隐藏该行时分隔线会一起消失。
final class RowStack: NSStackView {
    var showsTopRule = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsTopRule else { return }
        Theme.separator.setFill()
        NSRect(
            x: Theme.Spacing.l,
            y: bounds.maxY - 1,
            width: max(0, bounds.width - Theme.Spacing.l * 2),
            height: 1
        ).fill()
    }
}

final class FormPane: NSView {
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        // 内容超出时才显示滚动条：短页面不留空槽，长页面有明确的可滚动提示
        scroll.scrollerStyle = .legacy
        scroll.autohidesScrollers = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        addSubview(scroll)

        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Theme.Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
        ])
    }

    /// 内容自然高度（含上下 16pt 内边距），用于按最高分页给设置窗定高
    var measuredContentHeight: CGFloat {
        layoutSubtreeIfNeeded()
        return stack.fittingSize.height + 32
    }

    func addTitle(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.Font.section
        label.textColor = .secondaryLabelColor
        let wrapper = NSStackView(views: [label])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.edgeInsets = NSEdgeInsets(top: 14, left: 2, bottom: 0, right: 0)
        addFullWidth(wrapper)
    }

    @discardableResult
    /// 切回某个分页时回到顶部，避免停在上次或布局调整后的中段
    func scrollToTop() {
        layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private var scrollerShown = false

    override func layout() {
        super.layout()
        updateScroller()
    }

    /// 只在「需要/不需要」翻转时改动，避免 legacy 滚动条占宽触发反复布局
    private func updateScroller() {
        let needed = document.frame.height > scroll.contentView.bounds.height + 1
        guard needed != scrollerShown else { return }
        scrollerShown = needed
        scroll.hasVerticalScroller = needed
    }

    func addCard(_ rows: [NSView]) -> NSStackView? {
        guard !rows.isEmpty else { return nil }
        let card = CardView()
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 0

        for (index, row) in rows.enumerated() {
            card.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: card.widthAnchor).isActive = true
            // 首行不画线，卡片上缘留白已经足够分层
            (row as? RowStack)?.showsTopRule = index > 0
        }
        addFullWidth(card)
        return card
    }

    /// 放入不套卡片的整块内容（如关于页的居中图标区）
    func addBlock(_ view: NSView) {
        addFullWidth(view)
    }

    private func addFullWidth(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

enum FormRow {
    static func make(
        title: String,
        detail: String? = nil,
        accessory: NSView? = nil
    ) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Theme.Font.body
        titleLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [titleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        if let detail {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = Theme.Font.footnote
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.lineBreakMode = .byTruncatingTail
            labels.addArrangedSubview(detailLabel)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = RowStack(views: [labels, spacer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Theme.Spacing.m
        row.edgeInsets = NSEdgeInsets(
            top: 9,
            left: Theme.Spacing.l,
            bottom: 9,
            right: Theme.Spacing.l
        )
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if let accessory {
            accessory.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            row.addArrangedSubview(accessory)
        }
        return row
    }

    static func noteRow(_ text: String) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Theme.Font.footnote
        label.textColor = .secondaryLabelColor
        let row = RowStack(views: [label])
        row.orientation = .vertical
        row.alignment = .leading
        row.edgeInsets = NSEdgeInsets(
            top: 9,
            left: Theme.Spacing.l,
            bottom: 10,
            right: Theme.Spacing.l
        )
        return row
    }

    /// 右列统一宽度：各行控件组占同样宽度，左边缘才会对齐
    static let trailingWidth: CGFloat = 300

    /// 把一行右侧的多个控件收进同宽容器，输入框用 `textField(width: nil)` 自适应剩余空间
    static func trailing(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let group = NSStackView(views: views)
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = spacing
        group.distribution = .fill
        group.translatesAutoresizingMaskIntoConstraints = false
        group.widthAnchor.constraint(equalToConstant: trailingWidth).isActive = true
        return group
    }

    /// 输入框 + 左侧辅助控件（预设下拉、拉取按钮）。
    /// 辅助控件放左边而不是右边：输入框都定宽，右边缘才能对齐且不长出一条空槽。
    static func group(_ field: NSView, control: NSView? = nil) -> NSStackView {
        let group = NSStackView(views: control.map { [$0, field] } ?? [field])
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = Theme.Spacing.s
        group.translatesAutoresizingMaskIntoConstraints = false
        return group
    }

    static func textField(width: CGFloat? = 240) -> NSTextField {
        let field = NSTextField()
        field.font = Theme.Font.body
        field.bezelStyle = .roundedBezel
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else {
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return field
    }

    static func secureField(width: CGFloat? = 240) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.font = Theme.Font.body
        field.bezelStyle = .roundedBezel
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else {
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return field
    }

    static func popup(width: CGFloat = 240) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = Theme.Font.body
        popup.controlSize = .regular
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        return popup
    }

    static func button(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = Theme.Font.footnote
        return button
    }

    static func switchButton(isOn: Bool, target: AnyObject?, action: Selector) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.target = target
        toggle.action = action
        return toggle
    }

    /// 与滑块并排的数值输入框：既能拖动也能直接键入精确值
    static func valueField(
        _ text: String,
        width: CGFloat = 52,
        target: AnyObject?,
        action: Selector
    ) -> NSTextField {
        let field = NSTextField(string: text)
        field.font = Theme.Font.monoDigits
        field.alignment = .right
        field.controlSize = .small
        field.bezelStyle = .roundedBezel
        field.target = target
        field.action = action
        // 回车和失焦都提交，避免用户输入后直接点保存被丢掉
        field.cell?.sendsActionOnEndEditing = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    static func valueLabel(_ text: String, width: CGFloat = 52) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.Font.monoDigits
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }
}

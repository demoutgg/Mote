// 设置界面通用组件：卡片分区、表单行和滚动容器；不涉及配置读写。
import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 设置卡片容器：底色与描边跟随深浅色外观重设
final class CardView: NSStackView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
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
        stack.spacing = 6
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

    func addTitle(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
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

        for row in rows {
            card.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: card.widthAnchor).isActive = true
        }
        addFullWidth(card)
        return card
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
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [titleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        if let detail {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = .systemFont(ofSize: 11)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.lineBreakMode = .byTruncatingTail
            labels.addArrangedSubview(detailLabel)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [labels, spacer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if let accessory {
            accessory.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            row.addArrangedSubview(accessory)
        }
        return row
    }

    static func noteRow(_ text: String) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let row = NSStackView(views: [label])
        row.orientation = .vertical
        row.alignment = .leading
        row.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)
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

    static func textField(width: CGFloat? = 240) -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 12)
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 22).isActive = true
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
        field.font = .systemFont(ofSize: 12)
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 22).isActive = true
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
        popup.font = .systemFont(ofSize: 12)
        popup.controlSize = .small
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        return popup
    }

    static func button(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        return button
    }

    static func switchButton(isOn: Bool, target: AnyObject?, action: Selector) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.target = target
        toggle.action = action
        return toggle
    }

    static func valueLabel(_ text: String, width: CGFloat = 52) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }
}

// 设置窗口顶部导航：图标在上、文字在下，选中项浅色胶囊，整组居中。
// 系统工具栏在有窗口标题时会把图标项挤到左侧，所以这里自绘，换取「标题行 + Tab 行」两行居中的版式。
import AppKit

final class SettingsTabBar: NSView {
    struct Item {
        let label: String
        let symbol: String
    }

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0
    private var buttons: [ItemView] = []

    private static let itemWidth: CGFloat = 66
    private static let itemHeight: CGFloat = 56
    private static let gap: CGFloat = 6

    init(items: [Item]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for (index, item) in items.enumerated() {
            let button = ItemView(item: item)
            button.onClick = { [weak self] in self?.select(index) }
            addSubview(button)
            buttons.append(button)
        }
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: totalWidth, height: Self.itemHeight)
    }

    override func layout() {
        super.layout()
        var x = (bounds.width - totalWidth) / 2
        for button in buttons {
            button.frame = NSRect(
                x: x,
                y: (bounds.height - Self.itemHeight) / 2,
                width: Self.itemWidth,
                height: Self.itemHeight
            )
            x += Self.itemWidth + Self.gap
        }
    }

    func select(_ index: Int) {
        guard index >= 0, index < buttons.count, index != selectedIndex else { return }
        selectedIndex = index
        updateSelection()
        onSelect?(index)
    }

    private var totalWidth: CGFloat {
        let count = CGFloat(buttons.count)
        return count * Self.itemWidth + max(0, count - 1) * Self.gap
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            button.isSelected = index == selectedIndex
        }
    }

    private final class ItemView: NSView {
        var onClick: (() -> Void)?
        var isSelected = false {
            didSet { refreshColors() }
        }

        private let icon = NSImageView()
        private let title = NSTextField(labelWithString: "")

        init(item: SettingsTabBar.Item) {
            super.init(frame: .zero)
            icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.label)?
                .withSymbolConfiguration(.init(pointSize: 19, weight: .regular))
            icon.imageScaling = .scaleNone
            addSubview(icon)

            title.stringValue = item.label
            title.font = .systemFont(ofSize: 11, weight: .medium)
            title.alignment = .center
            addSubview(title)

            setAccessibilityRole(.button)
            setAccessibilityLabel(item.label)
            refreshColors()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            let titleHeight: CGFloat = 14
            title.frame = NSRect(x: 0, y: 7, width: bounds.width, height: titleHeight)
            icon.sizeToFit()
            icon.frame = NSRect(
                x: (bounds.width - icon.frame.width) / 2,
                y: title.frame.maxY + 4,
                width: icon.frame.width,
                height: icon.frame.height
            )
        }

        override func draw(_ dirtyRect: NSRect) {
            guard isSelected else { return }
            let path = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 3, dy: 4),
                xRadius: Theme.Radius.small,
                yRadius: Theme.Radius.small
            )
            Theme.wellFill.setFill()
            path.fill()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            refreshColors()
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }

        private func refreshColors() {
            let color: NSColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            icon.contentTintColor = color
            title.textColor = color
            needsDisplay = true
        }
    }
}

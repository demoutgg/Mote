// 历史记录视图（纯 AppKit）：搜索、查看和复制最近 100 条；不负责写入历史。
import AppKit
import Combine

final class HistoryPane: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let store: HistoryStore

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scroll = SmoothScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private var cancellables = Set<AnyCancellable>()
    private var filtered: [HistoryEntry] = []

    private static let rowHeight: CGFloat = 54

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    init(store: HistoryStore) {
        self.store = store
        super.init(frame: .zero)
        setup()
        bind()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let card = CardView()
        card.orientation = .vertical
        card.spacing = 0
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.l),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])

        searchField.placeholderString = "搜索原文或译文"
        searchField.font = Theme.Font.body
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        clearButton.title = "清空"
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.font = Theme.Font.footnote
        clearButton.target = self
        clearButton.action = #selector(confirmClear)
        // 「清空」作用于整个列表，跟搜索框同一行右侧
        clearButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let searchRow = NSStackView(views: [searchField, clearButton])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = Theme.Spacing.s
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(searchRow)

        let divider = SeparatorView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(divider)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        // 默认的 .automatic 会按 inset 风格再缩一圈，行内容左右比搜索框多出 14pt
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(copySelected)

        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)

        emptyLabel.font = Theme.Font.body
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            searchRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            searchRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            divider.topAnchor.constraint(equalTo: searchRow.bottomAnchor, constant: Theme.Spacing.m),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Spacing.l),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.Spacing.l),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -10),
        ])

        menu = buildMenu()
    }

    private func bind() {
        store.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    private func reload() {
        let needle = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        filtered = needle.isEmpty
            ? store.entries
            : store.entries.filter { entry in
                entry.source.lowercased().contains(needle)
                    || entry.results.contains { $0.text.lowercased().contains(needle) }
            }
        tableView.reloadData()
        clearButton.isEnabled = !store.entries.isEmpty
        emptyLabel.stringValue = needle.isEmpty ? "还没有历史记录" : "没有匹配的记录"
        emptyLabel.isHidden = !filtered.isEmpty
        scroll.isHidden = filtered.isEmpty
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制原文", action: #selector(copySource), keyEquivalent: "")
        menu.addItem(withTitle: "复制译文", action: #selector(copyTarget), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard row < filtered.count else { return nil }
        let entry = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HistoryCell
            ?? HistoryCell(identifier: identifier)

        cell.configure(
            source: entry.source.replacingOccurrences(of: "\n", with: " "),
            date: Self.dateFormatter.string(from: entry.date),
            target: entry.results.first?.text.replacingOccurrences(of: "\n", with: " ")
                ?? entry.source.replacingOccurrences(of: "\n", with: " "),
            extra: entry.results.count > 1 ? "另有 \(entry.results.count - 1) 个结果" : nil
        )
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    @objc private func searchChanged() {
        reload()
    }

    /// 右键点在行上就用那一行；键盘选中后从菜单触发时 clickedRow 是 -1，回退到 selectedRow
    private var actionRow: Int {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        return row >= 0 && row < filtered.count ? row : -1
    }

    @objc private func copySelected() {
        guard actionRow >= 0 else { return }
        copy(filtered[actionRow].results.first?.text ?? filtered[actionRow].source)
    }

    @objc private func copySource() {
        guard actionRow >= 0 else { return }
        copy(filtered[actionRow].source)
    }

    @objc private func copyTarget() {
        guard actionRow >= 0 else { return }
        let entry = filtered[actionRow]
        copy(entry.results.first?.text ?? entry.source)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "清空全部历史记录？"
        alert.informativeText = "清空后无法恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.store.clear()
            }
        }
    }

}

private final class HistoryCell: NSTableCellView {
    private let sourceLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private let separator = SeparatorView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        sourceLabel.font = Theme.Font.bodyStrong
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.maximumNumberOfLines = 1
        sourceLabel.usesSingleLineMode = true
        dateLabel.font = Theme.Font.monoDigits
        dateLabel.textColor = .tertiaryLabelColor
        dateLabel.alignment = .right
        targetLabel.lineBreakMode = .byTruncatingTail
        targetLabel.font = Theme.Font.body
        targetLabel.textColor = .secondaryLabelColor
        targetLabel.maximumNumberOfLines = 1
        targetLabel.usesSingleLineMode = true

        for view in [sourceLabel, dateLabel, targetLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            sourceLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.l),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -Theme.Spacing.s),

            dateLabel.centerYAnchor.constraint(equalTo: sourceLabel.centerYAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.l),
            dateLabel.widthAnchor.constraint(equalToConstant: 96),

            targetLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: Theme.Spacing.xs),
            targetLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.l),
            targetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.l),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.l),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.l),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(source: String, date: String, target: String, extra: String?) {
        sourceLabel.stringValue = source
        dateLabel.stringValue = date

        // 富文本会覆盖 cell 的换行设置，段落样式得自己带上，否则长句直接被裁掉而不是省略
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(
            string: target,
            attributes: [
                .font: Theme.Font.body,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        if let extra {
            text.append(NSAttributedString(
                string: "  · " + extra,
                attributes: [
                    .font: Theme.Font.footnote,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        targetLabel.attributedStringValue = text
    }
}

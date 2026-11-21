// 历史记录窗口：搜索、复制和清理最近 100 条翻译；不负责翻译本身。
import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    var isEmbedded = false
    var onClose: () -> Void = {}

    @State private var query = ""
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !isEmbedded {
                    Text("历史记录")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("最近 100 条")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("清空") {
                    showClearConfirmation = true
                }
                .disabled(store.entries.isEmpty)
                if !isEmbedded {
                    Button("关闭") {
                        onClose()
                    }
                }
            }
            .padding(14)

            Divider()

            TextField("搜索原文或译文", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24))
                    Text(query.isEmpty ? "还没有历史记录" : "没有匹配的记录")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { entry in
                    HistoryRow(entry: entry) { text in
                        copy(text)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("清空全部历史记录？", isPresented: $showClearConfirmation) {
            Button("清空", role: .destructive) {
                store.clear()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var filtered: [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.entries }
        let needle = trimmed.lowercased()
        return store.entries.filter { entry in
            entry.source.lowercased().contains(needle)
                || entry.results.contains { $0.text.lowercased().contains(needle) }
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    var onCopy: (String) -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.source)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Spacer()
                Text(Self.dateFormatter.string(from: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(entry.results) { result in
                HStack(alignment: .top, spacing: 8) {
                    Text(result.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 118, alignment: .leading)

                    Text(result.text)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onCopy(result.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("复制译文")
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("复制原文") {
                onCopy(entry.source)
            }
            if let first = entry.results.first {
                Button("复制译文") {
                    onCopy(first.text)
                }
            }
        }
    }
}

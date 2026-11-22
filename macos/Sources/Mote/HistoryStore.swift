// 翻译历史：本地 JSON 保存最近 100 条，不上传。
import Combine
import Foundation

struct HistoryResult: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var source: String
    var targetLanguage: String
    var results: [HistoryResult]
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let limit = 100

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mote", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("history.json")
        load()
    }

    func add(source: String, targetLanguage: String, results: [ProviderResult]) {
        let items = results
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { HistoryResult(id: $0.id, title: $0.title, text: $0.text) }
        guard !items.isEmpty else { return }

        // 目标语言也算一次新的翻译，否则换语言后的译文会被当成重复丢掉
        if let latest = entries.first,
           latest.source == source,
           latest.targetLanguage == targetLanguage,
           latest.results.map(\.text) == items.map(\.text) {
            return
        }

        entries.insert(
            HistoryEntry(source: source, targetLanguage: targetLanguage, results: items),
            at: 0
        )
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return
        }
        entries = Array(decoded.prefix(limit))
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

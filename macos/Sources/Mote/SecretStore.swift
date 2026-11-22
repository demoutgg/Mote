// 本机密钥存储：写应用支持目录的 0600 文件。
// 不用钥匙串是因为每次 ad-hoc 重新签名后 ACL 失效，密钥会读不到。
import Foundation

enum SecretStore {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mote/secrets.json")
    }

    static func read(account: String = "api-key") -> String? {
        load()[account]
    }

    static func save(_ value: String, account: String = "api-key") {
        var items = load()
        if value.isEmpty {
            items.removeValue(forKey: account)
        } else {
            items[account] = value
        }

        let manager = FileManager.default
        try? manager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? manager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return items
    }
}


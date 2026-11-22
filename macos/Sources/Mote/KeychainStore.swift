import Foundation
import Security

enum KeychainStore {
    private static let service = "com.demoutgg.mote"
    private static let legacyService = "com.demoutgg.lingolite"

    static func read(account: String = "api-key") -> String? {
        read(account: account, service: service)
    }

    private static func read(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func migrateLegacyIfNeeded() {
        for account in ["api-key", "baidu-key"] {
            guard read(account: account) == nil else { continue }
            if let value = read(account: account, service: legacyService) {
                save(value, account: account)
            }
        }
    }

    static func save(_ value: String, account: String = "api-key") {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        guard !value.isEmpty else { return }

        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}


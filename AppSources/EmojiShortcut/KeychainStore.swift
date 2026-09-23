import Foundation
import Security

enum KeychainStore {
    private static let service = "com.ebiebimanman.emoji-shortcut"
    private static let legacyService = "com.emoji-shortcut.app"
    enum Provider {
        case jev

        var account: String {
            switch self {
            case .jev: "typesafe-api-key"
            }
        }
    }

    static func read(for provider: Provider = .jev) -> String? {
        read(service: service, account: provider.account)
            ?? read(service: legacyService, account: provider.account)
    }

    private static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String, for provider: Provider = .jev) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.account
        ]
        let data = Data(key.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

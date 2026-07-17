// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Security

/// Stores the AnkiWeb sync auth key. Never UserDefaults — it's a bearer
/// credential for the user's account.
enum Keychain {
    private static let service = "com.ankiapp.ios.sync"
    private static let account = "hkey"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func saveHkey(_ hkey: String) {
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(hkey.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadHkey() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteHkey() {
        SecItemDelete(query as CFDictionary)
    }
}

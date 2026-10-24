import Foundation
import Security

/// Everything needed to call the API and to sign in again. Stored only in the Keychain.
struct TokenSet: Codable, Sendable {
    var issuedClientID: String
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date
    var grantedScopes: [String]
    var accountSubject: String?
    var redirectURI: String
}

enum TokenStore {
    private static let service = "com.w7rp.calorietracker.openai"
    private static let account = "tokens"

    static func load() -> TokenSet? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    static func save(_ tokens: TokenSet) throws {
        let data = try JSONEncoder().encode(tokens)
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

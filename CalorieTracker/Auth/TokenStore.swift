import Foundation

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
        Keychain.read(service: service, account: account).flatMap { try? JSONDecoder().decode(TokenSet.self, from: $0) }
    }

    static func save(_ tokens: TokenSet) throws {
        try Keychain.write(JSONEncoder().encode(tokens), service: service, account: account)
    }

    static func delete() {
        Keychain.delete(service: service, account: account)
    }
}

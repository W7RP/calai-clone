import Foundation

/// The query on the loopback redirect, whether it arrived through the listener or was pasted back.
struct AuthCallback: Sendable, Equatable {
    let code: String?
    let state: String?
    let issuedClientID: String?
    let error: String?

    init(url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        code = value("code")
        state = value("state")
        issuedClientID = value("client_id")
        error = value("error")
    }

    /// Accepts a full URL or a bare request target like "/auth/callback?code=...".
    init?(pasted text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = trimmed.hasPrefix("/") ? "http://127.0.0.1\(trimmed)" : trimmed
        guard let url = URL(string: full), url.path == OpenAIAuthConfig.callbackPath else { return nil }
        self.init(url: url)
    }
}

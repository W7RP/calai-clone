import Foundation

/// Which provider is active and how each one is set up. Keys go to the Keychain; everything else is
/// non-secret and lives in UserDefaults.
enum AIProviderSettings {
    private static let providerKey = "aiProvider"
    private static let customBaseURLKey = "aiCustomBaseURL"

    static var activeProvider: ProviderKind {
        get { UserDefaults.standard.string(forKey: providerKey).flatMap { ProviderKind(rawValue: $0) } ?? .chatGPT }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    /// ChatGPT keeps the original "aiModel" key so a model picked before providers existed still applies.
    static func modelDefaultsKey(for kind: ProviderKind) -> String {
        kind == .chatGPT ? "aiModel" : "aiModel.\(kind.rawValue)"
    }

    /// The saved model, or the provider's suggestion.
    static func model(for kind: ProviderKind) -> String {
        let saved = UserDefaults.standard.string(forKey: modelDefaultsKey(for: kind))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty { return saved }
        return kind.suggestedModel ?? ""
    }

    static func setModel(_ model: String, for kind: ProviderKind) {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelDefaultsKey(for: kind))
    }

    static var customBaseURL: String {
        get { UserDefaults.standard.string(forKey: customBaseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: customBaseURLKey) }
    }

    /// The saved configuration for `kind`. Missing pieces are reported when a request is attempted.
    static func config(for kind: ProviderKind) -> ProviderConfig {
        ProviderConfig(kind: kind, model: model(for: kind), apiKey: APIKeyStore.key(for: kind),
                       baseURL: kind == .openAICompatible ? CustomEndpoint.normalizedBaseURL(customBaseURL) : nil)
    }
}

/// User-entered provider keys. Never logged, never shown again in full after saving.
enum APIKeyStore {
    private static let service = "com.w7rp.calorietracker.apikeys"

    static func key(for kind: ProviderKind) -> String? {
        Keychain.read(service: service, account: kind.rawValue).map { String(decoding: $0, as: UTF8.self) }
    }

    static func save(_ key: String, for kind: ProviderKind) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(for: kind) }
        try Keychain.write(Data(trimmed.utf8), service: service, account: kind.rawValue)
    }

    static func delete(for kind: ProviderKind) {
        Keychain.delete(service: service, account: kind.rawValue)
    }

    /// "sk-…3f9Q": enough to recognise which key is saved without exposing it.
    static func masked(_ key: String) -> String {
        guard key.count > 12 else { return "••••••••" }
        return "\(key.prefix(3))…\(key.suffix(4))"
    }
}

enum CustomEndpoint {
    /// Accepts "https://openrouter.ai/api/v1", "http://192.168.1.20:11434/v1/" or a bare host, and returns the
    /// base that `/chat/completions` and `/models` hang off. Nil when it isn't a usable http(s) URL.
    static func normalizedBaseURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        for suffix in ["/chat/completions", "/completions"] where trimmed.hasSuffix(suffix) {
            trimmed.removeLast(suffix.count)
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }
}

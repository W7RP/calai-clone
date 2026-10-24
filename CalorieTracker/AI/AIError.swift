import Foundation

/// What went wrong with an AI call, in terms the user can act on. Manual entry always keeps working.
enum AIError: LocalizedError, Equatable {
    // Setup
    case notConnected
    case sessionEnded
    case missingKey(ProviderKind)
    case missingServer
    case noModel(ProviderKind)
    // ChatGPT plan
    case usageLimit
    case notEligible
    // Any provider
    case invalidKey(ProviderKind)
    case quotaExceeded(ProviderKind)
    case rateLimited(ProviderKind)
    case temporarilyUnavailable(ProviderKind)
    case modelNotFound(ProviderKind, detail: String?)
    case unsupported(param: String?)
    case rejected(ProviderKind, status: Int, detail: String)
    case refused(String?)
    case incomplete(String)
    case network(String)
    case offline
    // The answer itself
    case unreadable
    case implausible(String)
    case nothingFound(String?)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Connect your ChatGPT account in Settings → AI provider to use AI logging."
        case .sessionEnded: "Your ChatGPT connection ended. Connect again in Settings → AI provider."
        case .missingKey(let kind): "Add your \(kind.name) API key in Settings → AI provider."
        case .missingServer: "Enter the server address in Settings → AI provider."
        case .noModel(let kind): "Pick a \(kind.name) model in Settings → AI provider."
        case .usageLimit: "You've hit the usage limit for this app on your ChatGPT plan. Check ChatGPT → Settings → Usage, or log manually for now."
        case .notEligible: "Plan usage isn't available for this ChatGPT account."
        case .invalidKey(let kind): "\(kind.name) didn't accept the API key. Check it in Settings → AI provider."
        case .quotaExceeded(let kind): "Your \(kind.name) account is out of credit or over its quota. Check billing on the provider's site."
        case .rateLimited(let kind): "\(kind.name) is rate-limiting requests. Wait a moment and try again."
        case .temporarilyUnavailable(let kind): "\(kind.name) is temporarily unavailable. Try again in a minute."
        case .modelNotFound(let kind, let detail):
            "\(kind.name) doesn't offer that model to this account. Pick another in Settings → AI provider.\(detail.map { " (\($0))" } ?? "")"
        case .unsupported(let param): "The request used something this route doesn't support\(param.map { " (\($0))" } ?? "")."
        case .rejected(let kind, let status, let detail): "\(kind.name) rejected the request (HTTP \(status)). \(detail)"
        case .refused(let reason): reason.map { "The model declined: \($0)" } ?? "The model declined to answer. Try a different photo or describe the meal."
        case .incomplete(let reason): "The answer was cut off (\(reason)). Try again."
        case .network(let detail): "Network problem: \(detail). Try again."
        case .offline: "You're offline. AI logging needs a connection; manual entry still works."
        case .unreadable: "The answer wasn't in the expected format. Try again or log manually."
        case .implausible(let reason): "The estimate didn't add up (\(reason)). Try again or log manually."
        case .nothingFound(let note): note ?? "No food was recognised."
        }
    }

    /// Worth trying the same request again after a pause.
    var isTransient: Bool {
        switch self {
        case .rateLimited, .temporarilyUnavailable, .network: true
        default: false
        }
    }

    // MARK: ChatGPT route

    /// Maps a structured `error.code` from the Sign in with ChatGPT Responses route (docs: Errors and recovery).
    static func fromCode(_ code: String?, param: String? = nil, status: Int = 0, message: String? = nil) -> AIError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": .usageLimit
        case "subscription_sharing_user_not_eligible": .notEligible
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": .temporarilyUnavailable(.chatGPT)
        case "subscription_sharing_unsupported_capability": .unsupported(param: param)
        // Not proof of revocation on its own, so the session is kept; reconnecting is the user's call.
        case "subscription_sharing_invalid_user":
            .rejected(.chatGPT, status: status, detail: "ChatGPT didn't accept this account. Try reconnecting in Settings.")
        case "rate_limit_exceeded": .rateLimited(.chatGPT)
        case "server_error": .temporarilyUnavailable(.chatGPT)
        default: .rejected(.chatGPT, status: status, detail: message ?? code ?? "")
        }
    }

    /// Errors before the stream opens may be `{"error":{...}}` or `{"detail":"..."}`.
    static func fromHTTP(status: Int, body: String) -> AIError {
        let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            return fromCode(error["code"] as? String, param: error["param"] as? String, status: status,
                            message: error["message"] as? String)
        }
        if status == 503 { return .temporarilyUnavailable(.chatGPT) }
        if status == 429 { return .rateLimited(.chatGPT) }
        return .rejected(.chatGPT, status: status, detail: (json?["detail"] as? String) ?? "")
    }

    // MARK: API-key providers

    /// One mapper for Anthropic, OpenAI, Gemini and OpenAI-compatible error bodies. They differ in shape:
    /// Anthropic `{"type":"error","error":{"type","message"}}`, OpenAI `{"error":{"message","type","code"}}`,
    /// Gemini `{"error":{"code":400,"status":"INVALID_ARGUMENT","message","details":[{"reason"}]}}`.
    static func fromProviderHTTP(provider: ProviderKind, status: Int, body: String) -> AIError {
        let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let message = (error?["message"] as? String) ?? (json?["message"] as? String) ?? (json?["detail"] as? String)
            ?? (error == nil && json == nil ? String(body.prefix(200)) : "")
        let reasons = ((error?["details"] as? [[String: Any]]) ?? []).compactMap { $0["reason"] as? String }
        let tags = Set(([error?["type"], error?["code"], error?["status"]].compactMap { $0 as? String } + reasons)
            .map { $0.lowercased() })

        if !tags.isDisjoint(with: ["insufficient_quota", "billing_error", "billing_hard_limit_reached"]) || status == 402 {
            return .quotaExceeded(provider)
        }
        if status == 401 || !tags.isDisjoint(with: ["authentication_error", "invalid_api_key", "api_key_invalid", "permission_error"])
            || (status == 403 && tags.contains("permission_denied")) {
            return .invalidKey(provider)
        }
        if !tags.isDisjoint(with: ["model_not_found", "not_found_error"]) || status == 404 {
            return .modelNotFound(provider, detail: message.isEmpty ? nil : String(message.prefix(160)))
        }
        if status == 429 || tags.contains("rate_limit_error") || tags.contains("resource_exhausted") {
            return .rateLimited(provider)
        }
        if status == 529 || status >= 500 || tags.contains("overloaded_error") || tags.contains("unavailable") {
            return .temporarilyUnavailable(provider)
        }
        return .rejected(provider, status: status, detail: String(message.prefix(300)))
    }

    static func from(_ error: URLError) -> AIError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: .offline
        case .timedOut: .network("the request timed out")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: .network("couldn't reach the server")
        case .networkConnectionLost: .network("the connection dropped")
        case .appTransportSecurityRequiresSecureConnection: .rejected(.openAICompatible, status: 0,
            detail: "This address needs https, or must be on your local network.")
        case .cancelled: .network("cancelled")
        default: .network(error.localizedDescription)
        }
    }
}

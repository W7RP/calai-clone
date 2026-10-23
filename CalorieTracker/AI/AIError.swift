import Foundation

/// What went wrong with an AI call, in terms the user can act on. Manual entry always keeps working.
enum AIError: LocalizedError, Equatable {
    case notConnected
    case sessionEnded
    case noModel
    case usageLimit
    case notEligible
    case temporarilyUnavailable
    case unsupported(param: String?)
    case rejected(status: Int, detail: String)
    case incomplete(String)
    case unreadable
    case nothingFound(String?)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Connect your ChatGPT account in Settings to use AI logging."
        case .sessionEnded: "Your ChatGPT connection ended. Connect again in Settings."
        case .noModel: "Pick a model in Settings → ChatGPT."
        case .usageLimit: "You've hit the usage limit for this app on your ChatGPT plan. Check ChatGPT → Settings → Usage, or log manually for now."
        case .notEligible: "Plan usage isn't available for this ChatGPT account."
        case .temporarilyUnavailable: "ChatGPT is temporarily unavailable. Try again in a minute."
        case .unsupported(let param): "The request used something this route doesn't support\(param.map { " (\($0))" } ?? "")."
        case .rejected(let status, let detail): "ChatGPT rejected the request (HTTP \(status)). \(detail)"
        case .incomplete(let reason): "The answer was cut off (\(reason)). Try again."
        case .unreadable: "The answer wasn't in the expected format. Try again or log manually."
        case .nothingFound(let note): note ?? "No food was recognised."
        }
    }

    /// Maps a structured `error.code` from the Responses API (docs: Errors and recovery).
    static func fromCode(_ code: String?, param: String? = nil, status: Int = 0, message: String? = nil) -> AIError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": .usageLimit
        case "subscription_sharing_user_not_eligible": .notEligible
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": .temporarilyUnavailable
        case "subscription_sharing_unsupported_capability": .unsupported(param: param)
        // Not proof of revocation on its own, so the session is kept; reconnecting is the user's call.
        case "subscription_sharing_invalid_user":
            .rejected(status: status, detail: "ChatGPT didn't accept this account. Try reconnecting in Settings.")
        default: .rejected(status: status, detail: message ?? code ?? "")
        }
    }

    /// Errors before the stream opens may be `{"error":{...}}` or `{"detail":"..."}`.
    static func fromHTTP(status: Int, body: String) -> AIError {
        let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            return fromCode(error["code"] as? String, param: error["param"] as? String, status: status,
                            message: error["message"] as? String)
        }
        if status == 503 { return .temporarilyUnavailable }
        return .rejected(status: status, detail: (json?["detail"] as? String) ?? "")
    }
}

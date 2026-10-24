import Foundation

/// One server-sent event from a streaming Responses call, reduced to what the app acts on.
enum ResponsesStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case completed
    case failed(code: String?, message: String?)
    case incomplete(reason: String?)
    case error(code: String?, message: String?)
    case other(type: String)

    /// Parses one SSE line. Each `data:` payload carries its own `type`, so `event:` lines and
    /// blank separators can be ignored (URLSession's line reader drops blank lines anyway).
    static func parse(line: String) -> ResponsesStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let type = json["type"] as? String else { return nil }

        let response = json["response"] as? [String: Any]
        switch type {
        case "response.output_text.delta":
            return .textDelta(json["delta"] as? String ?? "")
        case "response.completed":
            return .completed
        case "response.failed":
            let error = response?["error"] as? [String: Any]
            return .failed(code: error?["code"] as? String, message: error?["message"] as? String)
        case "response.incomplete":
            let details = response?["incomplete_details"] as? [String: Any]
            return .incomplete(reason: details?["reason"] as? String)
        case "error":
            let nested = json["error"] as? [String: Any]
            return .error(code: (json["code"] ?? nested?["code"]) as? String,
                          message: (json["message"] ?? nested?["message"]) as? String)
        default:
            return .other(type: type)
        }
    }
}

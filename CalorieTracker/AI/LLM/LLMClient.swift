import Foundation

/// One provider-neutral request: system instructions, a short conversation, and an optional output schema.
struct LLMRequest: Sendable {
    var system: String
    var messages: [LLMMessage]
    /// When set, providers that support schema-constrained output are asked to follow it.
    /// The prompt also describes the shape, so a provider that can't enforce it still gets it right most of the time.
    var schema: OutputSchema?
    /// Ceiling for the reply, for providers that require one. Thinking tokens count against it on some models.
    var maxOutputTokens = 16_000
}

struct LLMMessage: Sendable, Equatable {
    enum Role: Sendable { case user, assistant }

    var role: Role
    var parts: [LLMPart]

    static func user(_ parts: LLMPart...) -> LLMMessage { LLMMessage(role: .user, parts: parts) }
    static func assistant(_ text: String) -> LLMMessage { LLMMessage(role: .assistant, parts: [.text(text)]) }
}

enum LLMPart: Sendable, Equatable {
    case text(String)
    case image(Data, mimeType: String)

    var dataURL: String? {
        guard case .image(let data, let mime) = self else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}

struct LLMModel: Sendable, Hashable, Identifiable {
    let id: String
    let displayName: String?
    var label: String { displayName ?? id }
}

/// Everything a client needs to reach one provider. Built from settings, or from unsaved fields when testing.
struct ProviderConfig: Sendable, Equatable {
    var kind: ProviderKind
    var model: String
    var apiKey: String?
    var baseURL: URL?
}

protocol LLMClient: Sendable {
    var provider: ProviderKind { get }
    /// Returns the model's text reply. Throws `AIError` for anything the user should see.
    func complete(_ request: LLMRequest) async throws -> String
    func listModels() async throws -> [LLMModel]
}

// MARK: Transport

/// The one seam between the clients and the network, so tests can run every provider without it.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.network("No HTTP response") }
            return (data, http)
        } catch let error as URLError {
            throw AIError.from(error)
        }
    }
}

extension URLRequest {
    /// A JSON POST with a timeout that leaves room for a slow vision model but not forever.
    static func jsonPOST(_ url: URL, body: JSONValue, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body.serialized()
        return request
    }

    static func jsonGET(_ url: URL, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}

extension HTTPTransport {
    /// Sends and returns the body of a 2xx response; anything else becomes a provider-specific `AIError`.
    func sendExpectingSuccess(_ request: URLRequest, provider: ProviderKind) async throws -> Data {
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.fromProviderHTTP(provider: provider, status: response.statusCode,
                                           body: String(decoding: data.prefix(2_000), as: UTF8.self))
        }
        return data
    }
}

enum SchemaFallback {
    /// True when a 400-class error says the provider or model didn't accept the structured-output field,
    /// in which case the request is sent again without it and the prompt carries the format alone.
    static func isRejection(_ error: Error, mentioning keywords: [String]) -> Bool {
        guard let error = error as? AIError else { return false }
        if case .unsupported = error { return true }
        guard case .rejected(_, let status, let detail) = error, status == 400 || status == 422 else { return false }
        let lowered = detail.lowercased()
        return keywords.contains { lowered.contains($0) }
    }
}

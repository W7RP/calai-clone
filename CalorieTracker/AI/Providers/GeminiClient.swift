import Foundation

/// Google Gemini through `generateContent` with an AI Studio key. The key goes in a header, never the URL.
struct GeminiClient: LLMClient {
    let apiKey: String
    let model: String
    var transport: any HTTPTransport = URLSessionTransport()
    var baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    var provider: ProviderKind { .gemini }

    private var headers: [String: String] { ["x-goog-api-key": apiKey] }

    /// The models listing returns "models/gemini-…"; requests want the bare id.
    var modelID: String { model.hasPrefix("models/") ? String(model.dropFirst("models/".count)) : model }

    func complete(_ request: LLMRequest) async throws -> String {
        do {
            return try await send(request, useSchema: request.schema != nil)
        } catch let error where request.schema != nil && SchemaFallback.isRejection(error, mentioning: ["response_schema", "responseschema", "generation_config"]) {
            return try await send(request, useSchema: false)
        }
    }

    func body(for request: LLMRequest, useSchema: Bool) -> JSONValue {
        var config: JSONValue = ["responseMimeType": "application/json"]
        if useSchema, let schema = request.schema {
            config = config.setting("responseSchema", to: schema.root.geminiSchema)
        }
        return [
            "systemInstruction": ["parts": [["text": .string(request.system)]]],
            "contents": .array(request.messages.map(Self.content)),
            "generationConfig": config,
        ]
    }

    private func send(_ request: LLMRequest, useSchema: Bool) async throws -> String {
        // Built as a string: the ":" in "model:generateContent" must not be percent-encoded.
        guard !modelID.contains("/"), let url = URL(string: baseURL.absoluteString + "/models/\(modelID):generateContent") else {
            throw AIError.noModel(provider)
        }
        let data = try await transport.sendExpectingSuccess(
            .jsonPOST(url, body: body(for: request, useSchema: useSchema), headers: headers), provider: provider)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> String {
        struct Reply: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String?; let thought: Bool? }
                    let parts: [Part]?
                }
                let content: Content?
                let finishReason: String?
            }
            struct Feedback: Decodable { let blockReason: String? }
            let candidates: [Candidate]?
            let promptFeedback: Feedback?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw AIError.unreadable }
        if let blocked = reply.promptFeedback?.blockReason { throw AIError.refused("blocked (\(blocked.lowercased()))") }
        guard let candidate = reply.candidates?.first else { throw AIError.unreadable }
        switch candidate.finishReason {
        case "MAX_TOKENS": throw AIError.incomplete("reached the length limit")
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION", "IMAGE_SAFETY":
            throw AIError.refused("blocked (\(candidate.finishReason!.lowercased()))")
        default: break
        }
        // Thinking models can return thought summaries as separate parts; only the answer counts.
        let text = (candidate.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw AIError.unreadable }
        return text
    }

    private static func content(_ message: LLMMessage) -> JSONValue {
        let parts: [JSONValue] = message.parts.map { part in
            switch part {
            case .text(let text):
                return ["text": .string(text)]
            case .image(let data, let mime):
                return ["inlineData": ["mimeType": .string(mime), "data": .string(data.base64EncodedString())]]
            }
        }
        return ["role": message.role == .user ? "user" : "model", "parts": .array(parts)]
    }

    func listModels() async throws -> [LLMModel] {
        struct Listing: Decodable {
            struct Model: Decodable {
                let name: String
                let displayName: String?
                let supportedGenerationMethods: [String]?
            }
            let models: [Model]?
        }
        var components = URLComponents(url: baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "pageSize", value: "200")]
        let data = try await transport.sendExpectingSuccess(.jsonGET(components.url!, headers: headers), provider: provider)
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else { throw AIError.unreadable }
        return (listing.models ?? [])
            .filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") && $0.name.contains("gemini") }
            .map { LLMModel(id: $0.name.replacingOccurrences(of: "models/", with: ""), displayName: $0.displayName) }
    }
}

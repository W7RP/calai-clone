import Foundation

/// Claude through the Messages API with the user's own key.
struct AnthropicClient: LLMClient {
    let apiKey: String
    let model: String
    var transport: any HTTPTransport = URLSessionTransport()
    var baseURL = URL(string: "https://api.anthropic.com/v1")!

    var provider: ProviderKind { .anthropic }

    static let apiVersion = "2026-10-21"
    /// Server-side refusal fallback: if a safety classifier declines, the API reruns the request on a
    /// suitable model instead of returning nothing. Only the models below accept it.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    private var headers: [String: String] {
        ["x-api-key": apiKey, "anthropic-version": Self.apiVersion]
    }

    /// Optional request features. Each is dropped and the request re-sent if the API says it doesn't take it.
    struct Options: Equatable {
        var schema: Bool
        var fallbacks: Bool
    }

    func complete(_ request: LLMRequest) async throws -> String {
        var options = Options(schema: request.schema != nil, fallbacks: Self.supportsFallbacks(model))
        while true {
            do {
                return try await send(request, options: options)
            } catch let error {
                if options.fallbacks, SchemaFallback.isRejection(error, mentioning: ["fallback"]) {
                    options.fallbacks = false
                } else if options.schema,
                          SchemaFallback.isRejection(error, mentioning: ["output_config", "json_schema", "structured output"]) {
                    // Older models don't take structured outputs; the prompt still describes the JSON.
                    options.schema = false
                } else {
                    throw error
                }
            }
        }
    }

    func body(for request: LLMRequest, options: Options) -> JSONValue {
        var body: JSONValue = [
            "model": .string(model),
            "max_tokens": .number(Double(request.maxOutputTokens)),
            "system": .string(request.system),
            "messages": .array(request.messages.map(Self.message)),
        ]
        if options.schema, let schema = request.schema {
            body = body.setting("output_config", to: ["format": ["type": "json_schema", "schema": schema.root.jsonSchema]])
        }
        if options.fallbacks {
            body = body.setting("fallbacks", to: "default")
        }
        return body
    }

    static func supportsFallbacks(_ model: String) -> Bool {
        ["claude-opus-5", "claude-fable-5", "claude-sonnet-5-5"].contains { model.hasPrefix($0) }
    }

    private func send(_ request: LLMRequest, options: Options) async throws -> String {
        var headers = headers
        if options.fallbacks { headers["anthropic-beta"] = Self.fallbackBeta }
        let urlRequest = URLRequest.jsonPOST(baseURL.appending(path: "messages"),
                                             body: body(for: request, options: options), headers: headers)
        let data = try await transport.sendExpectingSuccess(urlRequest, provider: provider)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> String {
        struct Reply: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
            let stop_details: StopDetails?
            struct StopDetails: Decodable { let explanation: String? }
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw AIError.unreadable }
        switch reply.stop_reason {
        case "refusal": throw AIError.refused(reply.stop_details?.explanation)
        case "max_tokens": throw AIError.incomplete("reached the length limit")
        default: break
        }
        let text = reply.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw AIError.unreadable }
        return text
    }

    private static func message(_ message: LLMMessage) -> JSONValue {
        // Images go before text, which is what Claude's vision docs recommend.
        let ordered = message.parts.filter { $0.dataURL != nil } + message.parts.filter { $0.dataURL == nil }
        let content: [JSONValue] = ordered.map { part in
            switch part {
            case .text(let text):
                return ["type": "text", "text": .string(text)]
            case .image(let data, let mime):
                return ["type": "image",
                        "source": ["type": "base64", "media_type": .string(mime), "data": .string(data.base64EncodedString())]]
            }
        }
        return ["role": message.role == .user ? "user" : "assistant", "content": .array(content)]
    }

    func listModels() async throws -> [LLMModel] {
        struct Listing: Decodable {
            struct Model: Decodable { let id: String; let display_name: String? }
            let data: [Model]
        }
        var components = URLComponents(url: baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        let data = try await transport.sendExpectingSuccess(.jsonGET(components.url!, headers: headers), provider: provider)
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else { throw AIError.unreadable }
        return listing.data.map { LLMModel(id: $0.id, displayName: $0.display_name) }
    }
}

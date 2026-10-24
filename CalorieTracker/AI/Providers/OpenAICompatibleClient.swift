import Foundation

/// Any server with an OpenAI-style `/chat/completions` endpoint: OpenRouter, Ollama, LM Studio, vLLM, Groq,
/// Together, Mistral and so on. Support for `response_format` varies, so it degrades step by step.
struct OpenAICompatibleClient: LLMClient {
    let baseURL: URL
    let apiKey: String?
    let model: String
    var transport: any HTTPTransport = URLSessionTransport()

    var provider: ProviderKind { .openAICompatible }

    /// Strongest first. Each step is tried only if the server rejected the previous one.
    enum ResponseFormat: CaseIterable { case jsonSchema, jsonObject, none }

    private var headers: [String: String] {
        guard let apiKey, !apiKey.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(apiKey)"]
    }

    func complete(_ request: LLMRequest) async throws -> String {
        var formats: [ResponseFormat] = request.schema == nil ? [.jsonObject, .none] : ResponseFormat.allCases
        while true {
            let format = formats.removeFirst()
            do {
                return try await send(request, format: format)
            } catch let error where !formats.isEmpty && SchemaFallback.isRejection(error, mentioning: ["response_format", "json_schema", "json_object", "structured"]) {
                continue
            }
        }
    }

    func body(for request: LLMRequest, format: ResponseFormat) -> JSONValue {
        var messages: [JSONValue] = [["role": "system", "content": .string(request.system)]]
        messages += request.messages.map(Self.message)
        var body: JSONValue = ["model": .string(model), "messages": .array(messages)]
        switch format {
        case .jsonSchema:
            if let schema = request.schema {
                body = body.setting("response_format", to: ["type": "json_schema", "json_schema": [
                    "name": .string(schema.name), "strict": true, "schema": schema.root.jsonSchema,
                ]])
            }
        case .jsonObject:
            body = body.setting("response_format", to: ["type": "json_object"])
        case .none:
            break
        }
        return body
    }

    private func send(_ request: LLMRequest, format: ResponseFormat) async throws -> String {
        let urlRequest = URLRequest.jsonPOST(baseURL.appending(path: "chat/completions"),
                                             body: body(for: request, format: format), headers: headers)
        let data = try await transport.sendExpectingSuccess(urlRequest, provider: provider)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> String {
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String?; let refusal: String? }
                let message: Message?
                let finish_reason: String?
            }
            let choices: [Choice]?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), let choice = reply.choices?.first else {
            throw AIError.unreadable
        }
        if let refusal = choice.message?.refusal, !refusal.isEmpty { throw AIError.refused(refusal) }
        switch choice.finish_reason {
        case "length": throw AIError.incomplete("reached the length limit")
        case "content_filter": throw AIError.refused(nil)
        default: break
        }
        guard let text = choice.message?.content, !text.isEmpty else { throw AIError.unreadable }
        return text
    }

    private static func message(_ message: LLMMessage) -> JSONValue {
        guard message.role == .user else {
            let text = message.parts.compactMap { part -> String? in
                guard case .text(let text) = part else { return nil }
                return text
            }.joined()
            return ["role": "assistant", "content": .string(text)]
        }
        let content: [JSONValue] = message.parts.map { part in
            switch part {
            case .text(let text):
                return ["type": "text", "text": .string(text)]
            case .image:
                return ["type": "image_url", "image_url": ["url": .string(part.dataURL ?? "")]]
            }
        }
        return ["role": "user", "content": .array(content)]
    }

    func listModels() async throws -> [LLMModel] {
        let data = try await transport.sendExpectingSuccess(.jsonGET(baseURL.appending(path: "models"), headers: headers),
                                                            provider: provider)
        return try OpenAIModelListing.parse(data, chatOnly: false)
    }
}

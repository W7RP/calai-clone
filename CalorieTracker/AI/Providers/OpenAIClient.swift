import Foundation

/// Request bodies for OpenAI's Responses API, shared by the API-key client and the ChatGPT sign-in route.
enum ResponsesBody {
    /// `stream` is required on the ChatGPT route; `imageDetail` is left out there because the route's
    /// accepted parameters are narrower.
    static func make(model: String, request: LLMRequest, useSchema: Bool, stream: Bool, imageDetail: String?) -> JSONValue {
        var body: JSONValue = [
            "model": .string(model),
            "instructions": .string(request.system),
            "input": .array(request.messages.map { message(for: $0, imageDetail: imageDetail) }),
            "store": false,
        ]
        if stream { body = body.setting("stream", to: true) }
        if useSchema, let schema = request.schema {
            body = body.setting("text", to: ["format": [
                "type": "json_schema", "name": .string(schema.name), "strict": true, "schema": schema.root.jsonSchema,
            ]])
        }
        return body
    }

    private static func message(for message: LLMMessage, imageDetail: String?) -> JSONValue {
        let content: [JSONValue] = message.parts.map { part in
            switch part {
            case .text(let text):
                return ["type": message.role == .user ? "input_text" : "output_text", "text": .string(text)]
            case .image:
                var image: JSONValue = ["type": "input_image", "image_url": .string(part.dataURL ?? "")]
                if let imageDetail { image = image.setting("detail", to: .string(imageDetail)) }
                return image
            }
        }
        return ["role": message.role == .user ? "user" : "assistant", "content": .array(content)]
    }
}

/// OpenAI Platform with the user's API key, through the Responses API (non-streaming).
struct OpenAIClient: LLMClient {
    let apiKey: String
    let model: String
    var transport: any HTTPTransport = URLSessionTransport()
    var baseURL = URL(string: "https://api.openai.com/v1")!

    var provider: ProviderKind { .openAI }

    private var headers: [String: String] { ["Authorization": "Bearer \(apiKey)"] }

    func complete(_ request: LLMRequest) async throws -> String {
        do {
            return try await send(request, useSchema: request.schema != nil)
        } catch let error where request.schema != nil && SchemaFallback.isRejection(error, mentioning: ["text.format", "json_schema"]) {
            return try await send(request, useSchema: false)
        }
    }

    private func send(_ request: LLMRequest, useSchema: Bool) async throws -> String {
        let body = ResponsesBody.make(model: model, request: request, useSchema: useSchema, stream: false, imageDetail: "high")
        let data = try await transport.sendExpectingSuccess(
            .jsonPOST(baseURL.appending(path: "responses"), body: body, headers: headers), provider: provider)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> String {
        struct Reply: Decodable {
            struct Item: Decodable {
                struct Content: Decodable { let type: String; let text: String?; let refusal: String? }
                let type: String
                let content: [Content]?
            }
            struct Incomplete: Decodable { let reason: String? }
            struct Failure: Decodable { let code: String?; let message: String? }
            let status: String?
            let output: [Item]?
            let incomplete_details: Incomplete?
            let error: Failure?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw AIError.unreadable }
        if reply.status == "incomplete" { throw AIError.incomplete(reply.incomplete_details?.reason ?? "unknown") }
        if reply.status == "failed" {
            throw AIError.rejected(.openAI, status: 200, detail: reply.error?.message ?? reply.error?.code ?? "")
        }
        let contents = (reply.output ?? []).filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if let refusal = contents.first(where: { $0.type == "refusal" }) { throw AIError.refused(refusal.refusal) }
        let text = contents.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw AIError.unreadable }
        return text
    }

    func listModels() async throws -> [LLMModel] {
        let data = try await transport.sendExpectingSuccess(.jsonGET(baseURL.appending(path: "models"), headers: headers),
                                                            provider: provider)
        return try OpenAIModelListing.parse(data, chatOnly: true)
    }
}

enum OpenAIModelListing {
    /// `{"data":[{"id":...}]}`, the shape OpenAI and most compatible servers use.
    static func parse(_ data: Data, chatOnly: Bool) throws -> [LLMModel] {
        struct Listing: Decodable {
            struct Model: Decodable { let id: String; let name: String? }
            let data: [Model]
        }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else { throw AIError.unreadable }
        let excluded = ["embedding", "tts", "whisper", "transcribe", "dall-e", "moderation", "realtime", "audio",
                        "image", "search", "davinci", "babbage", "sora"]
        return listing.data
            .filter { model in !chatOnly || !excluded.contains { model.id.lowercased().contains($0) } }
            .map { LLMModel(id: $0.id, displayName: $0.name) }
            .sorted { $0.id < $1.id }
    }
}

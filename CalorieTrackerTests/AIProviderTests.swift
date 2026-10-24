import Foundation
import Synchronization
import Testing
@testable import CalorieTracker

// MARK: Test doubles

/// Replies with canned responses in order and records every request.
final class MockTransport: HTTPTransport, Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: String
    }

    private let state: Mutex<(replies: [Reply], requests: [URLRequest])>

    init(_ replies: [Reply]) { state = Mutex((replies, [])) }
    convenience init(status: Int = 200, _ body: String) { self.init([Reply(status: status, body: body)]) }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = state.withLock { state in
            state.requests.append(request)
            return state.replies.isEmpty ? Reply(status: 500, body: "no reply queued") : state.replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }
}

/// An `LLMClient` that returns scripted results and records the requests it got.
final class ScriptedClient: LLMClient, Sendable {
    enum Step: Sendable {
        case reply(String)
        case fail(AIError)
    }

    private let state: Mutex<(steps: [Step], requests: [LLMRequest])>
    init(_ steps: [Step]) { state = Mutex((steps, [])) }

    var provider: ProviderKind { .anthropic }
    var requests: [LLMRequest] { state.withLock { $0.requests } }

    func complete(_ request: LLMRequest) async throws -> String {
        let step: Step = state.withLock { state in
            state.requests.append(request)
            return state.steps.isEmpty ? Step.fail(.unreadable) : state.steps.removeFirst()
        }
        switch step {
        case .reply(let text): return text
        case .fail(let error): throw error
        }
    }

    func listModels() async throws -> [LLMModel] { [] }
}

final class BodyRecorder: Sendable {
    let bodies = Mutex<[JSONValue]>([])
}

private func json(_ request: URLRequest) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any])
}

private let sampleRequest = LLMRequest(
    system: "Be brief.",
    messages: [.user(.text("2 eggs"), .image(Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg"))],
    schema: FoodPrompt.schema)

private let goodEstimate = """
{"analysis":"Two fried eggs.","items":[{"name":"Fried egg","grams":100,"kcal":196,"protein_g":13.6,"carbs_g":0.8,\
"fat_g":15,"confidence":"medium","source":"estimate"}],"note":""}
"""

// MARK: JSON and schema

struct JSONValueTests {
    @Test func keepsKeyOrderAndEscapes() {
        let value: JSONValue = ["b": 1, "a": ["x": "line\n\"quoted\" \\ tab\t"], "c": [true, .null, 0.5]]
        let text = String(decoding: value.serialized(), as: UTF8.self)
        #expect(text == #"{"b":1,"a":{"x":"line\n\"quoted\" \\ tab\t"},"c":[true,null,0.5]}"#)
    }

    @Test func roundTripsThroughFoundation() throws {
        let value: JSONValue = ["name": "Crème brûlée 🍮", "n": -12.25, "control": "\u{01}"]
        let parsed = try #require(try JSONSerialization.jsonObject(with: value.serialized()) as? [String: Any])
        #expect(parsed["name"] as? String == "Crème brûlée 🍮")
        #expect(parsed["n"] as? Double == -12.25)
        #expect(parsed["control"] as? String == "\u{01}")
    }

    @Test func strictJSONSchemaClosesEveryObject() throws {
        let schema = FoodPrompt.schema.root.jsonSchema
        let text = String(decoding: schema.serialized(), as: UTF8.self)
        #expect(text.hasPrefix(#"{"type":"object","properties":{"analysis":"#), "analysis must come first")
        let root = try #require(try JSONSerialization.jsonObject(with: schema.serialized()) as? [String: Any])
        #expect(root["additionalProperties"] as? Bool == false)
        #expect(root["required"] as? [String] == ["analysis", "items", "note"])
        let items = try #require((root["properties"] as? [String: Any])?["items"] as? [String: Any])
        let item = try #require(items["items"] as? [String: Any])
        #expect(item["additionalProperties"] as? Bool == false)
        #expect((item["required"] as? [String])?.count == 8)
    }

    @Test func geminiSchemaUsesOpenAPIDialect() throws {
        let root = try #require(try JSONSerialization.jsonObject(with: FoodPrompt.schema.root.geminiSchema.serialized()) as? [String: Any])
        #expect(root["type"] as? String == "OBJECT")
        #expect(root["additionalProperties"] == nil)
        #expect(root["propertyOrdering"] as? [String] == ["analysis", "items", "note"])
    }
}

// MARK: Providers

struct AnthropicClientTests {
    @Test func buildsMessagesRequest() async throws {
        let transport = MockTransport(#"{"content":[{"type":"text","text":"{}"}],"stop_reason":"end_turn"}"#)
        let client = AnthropicClient(apiKey: "sk-ant-test", model: "claude-opus-5-5", transport: transport)
        #expect(try await client.complete(sampleRequest) == "{}")

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == AnthropicClient.apiVersion)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == AnthropicClient.fallbackBeta)
        let body = try json(request)
        #expect(body["system"] as? String == "Be brief.")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["temperature"] == nil)
        let format = try #require((body["output_config"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let content = try #require(((body["messages"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["image", "text"], "image goes before text")
        #expect((content[0]["source"] as? [String: Any])?["media_type"] as? String == "image/jpeg")
    }

    @Test func noFallbackParameterOnOlderModels() async throws {
        let transport = MockTransport(#"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn"}"#)
        _ = try await AnthropicClient(apiKey: "k", model: "claude-haiku-4-5", transport: transport).complete(sampleRequest)
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(try json(request)["fallbacks"] == nil)
    }

    @Test func dropsStructuredOutputWhenRejected() async throws {
        let transport = MockTransport([
            .init(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"output_config.format: not supported on this model"}}"#),
            .init(status: 200, body: #"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn"}"#),
        ])
        let client = AnthropicClient(apiKey: "k", model: "claude-haiku-4-5", transport: transport)
        #expect(try await client.complete(sampleRequest) == "ok")
        #expect(transport.requests.count == 2)
        #expect(try json(transport.requests[1])["output_config"] == nil)
    }

    @Test func mapsStopReasonsAndErrors() async throws {
        #expect(throws: AIError.refused("not food")) {
            try AnthropicClient.parse(Data(#"{"content":[],"stop_reason":"refusal","stop_details":{"explanation":"not food"}}"#.utf8))
        }
        #expect(throws: AIError.incomplete("reached the length limit")) {
            try AnthropicClient.parse(Data(#"{"content":[{"type":"text","text":"{"}],"stop_reason":"max_tokens"}"#.utf8))
        }
        let unauthorized = MockTransport(status: 401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        await #expect(throws: AIError.invalidKey(.anthropic)) {
            try await AnthropicClient(apiKey: "bad", model: "m", transport: unauthorized).complete(sampleRequest)
        }
        let overloaded = MockTransport(status: 529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        await #expect(throws: AIError.temporarilyUnavailable(.anthropic)) {
            try await AnthropicClient(apiKey: "k", model: "m", transport: overloaded).complete(sampleRequest)
        }
    }
}

struct OpenAIClientTests {
    @Test func buildsStrictResponsesRequest() async throws {
        let reply = #"{"status":"completed","output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"{\"items\":[]}"}]}]}"#
        let transport = MockTransport(reply)
        let client = OpenAIClient(apiKey: "sk-test", model: "gpt-6-sol", transport: transport)
        #expect(try await client.complete(sampleRequest) == #"{"items":[]}"#)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try json(request)
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] == nil)
        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["strict"] as? Bool == true)
        #expect(format["name"] as? String == "food_estimate")
        let content = try #require(((body["input"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        let image = try #require(content.first { $0["type"] as? String == "input_image" })
        #expect((image["image_url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(image["detail"] as? String == "high")
    }

    @Test func mapsQuotaRateLimitAndRefusal() async throws {
        let quota = MockTransport(status: 429, #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}"#)
        await #expect(throws: AIError.quotaExceeded(.openAI)) {
            try await OpenAIClient(apiKey: "k", model: "m", transport: quota).complete(sampleRequest)
        }
        let limited = MockTransport(status: 429, #"{"error":{"message":"Rate limit reached","type":"requests","code":"rate_limit_exceeded"}}"#)
        await #expect(throws: AIError.rateLimited(.openAI)) {
            try await OpenAIClient(apiKey: "k", model: "m", transport: limited).complete(sampleRequest)
        }
        #expect(throws: AIError.refused("I can't help with that.")) {
            try OpenAIClient.parse(Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"I can't help with that."}]}]}"#.utf8))
        }
        #expect(throws: AIError.incomplete("max_output_tokens")) {
            try OpenAIClient.parse(Data(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#.utf8))
        }
    }

    @Test func modelListSkipsNonChatModels() throws {
        let models = try OpenAIModelListing.parse(Data(#"{"data":[{"id":"gpt-6-sol"},{"id":"text-embedding-3-large"},{"id":"gpt-6-luna"},{"id":"tts-2"}]}"#.utf8), chatOnly: true)
        #expect(models.map(\.id) == ["gpt-6-luna", "gpt-6-sol"])
    }
}

struct GeminiClientTests {
    @Test func buildsGenerateContentRequestWithKeyInHeader() async throws {
        let reply = #"{"candidates":[{"content":{"parts":[{"text":"thinking…","thought":true},{"text":"{\"items\":[]}"}]},"finishReason":"STOP"}]}"#
        let transport = MockTransport(reply)
        let client = GeminiClient(apiKey: "AIza-test", model: "models/gemini-3.8-flash", transport: transport)
        #expect(try await client.complete(sampleRequest) == #"{"items":[]}"#, "thought parts are skipped")

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.url?.query == nil, "the key must not be in the URL")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
        let body = try json(request)
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect((config["responseSchema"] as? [String: Any])?["type"] as? String == "OBJECT")
        let parts = try #require(((body["contents"] as? [[String: Any]])?.first)?["parts"] as? [[String: Any]])
        let inline = try #require(parts.compactMap { $0["inlineData"] as? [String: Any] }.first)
        #expect(inline["mimeType"] as? String == "image/jpeg")
    }

    @Test func mapsSafetyAndKeyErrors() async throws {
        #expect(throws: AIError.refused("blocked (safety)")) {
            try GeminiClient.parse(Data(#"{"candidates":[{"finishReason":"SAFETY"}]}"#.utf8))
        }
        let badKey = MockTransport(status: 400, #"{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"#)
        await #expect(throws: AIError.invalidKey(.gemini)) {
            try await GeminiClient(apiKey: "bad", model: "gemini-3.8-flash", transport: badKey).complete(sampleRequest)
        }
    }

    @Test func assistantTurnsUseModelRole() throws {
        var request = sampleRequest
        request.messages.append(.assistant("{}"))
        let body = GeminiClient(apiKey: "k", model: "m").body(for: request, useSchema: true)
        let parsed = try #require(try JSONSerialization.jsonObject(with: body.serialized()) as? [String: Any])
        let contents = try #require(parsed["contents"] as? [[String: Any]])
        #expect(contents.map { $0["role"] as? String } == ["user", "model"])
    }
}

struct OpenAICompatibleClientTests {
    @Test func stepsDownResponseFormatsAndOmitsEmptyKey() async throws {
        let ok = #"{"choices":[{"message":{"content":"{}"},"finish_reason":"stop"}]}"#
        let transport = MockTransport([
            .init(status: 400, body: #"{"error":{"message":"response_format json_schema is not supported"}}"#),
            .init(status: 400, body: #"{"error":{"message":"Unknown field response_format"}}"#),
            .init(status: 200, body: ok),
        ])
        let base = try #require(CustomEndpoint.normalizedBaseURL("http://192.168.1.20:11434/v1/"))
        let client = OpenAICompatibleClient(baseURL: base, apiKey: nil, model: "llava", transport: transport)
        #expect(try await client.complete(sampleRequest) == "{}")

        let requests = transport.requests
        #expect(requests.count == 3)
        #expect(requests[0].url?.absoluteString == "http://192.168.1.20:11434/v1/chat/completions")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect((try json(requests[0])["response_format"] as? [String: Any])?["type"] as? String == "json_schema")
        #expect((try json(requests[1])["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        #expect(try json(requests[2])["response_format"] == nil)
        let messages = try #require(try json(requests[0])["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "system")
    }

    @Test func unrelatedBadRequestIsNotRetried() async throws {
        let transport = MockTransport(status: 400, #"{"error":{"message":"model llava does not support images"}}"#)
        let client = OpenAICompatibleClient(baseURL: URL(string: "https://example.com/v1")!, apiKey: "k", model: "llava", transport: transport)
        await #expect(throws: AIError.rejected(.openAICompatible, status: 400, detail: "model llava does not support images")) {
            try await client.complete(sampleRequest)
        }
        #expect(transport.requests.count == 1)
    }

    @Test func normalizesBaseURLs() {
        #expect(CustomEndpoint.normalizedBaseURL("openrouter.ai/api/v1")?.absoluteString == "https://openrouter.ai/api/v1")
        #expect(CustomEndpoint.normalizedBaseURL("https://api.groq.com/openai/v1/chat/completions")?.absoluteString
                == "https://api.groq.com/openai/v1")
        #expect(CustomEndpoint.normalizedBaseURL("ftp://example.com") == nil)
        #expect(CustomEndpoint.normalizedBaseURL("  ") == nil)
    }
}

struct ChatGPTClientTests {
    @Test func fallsBackWhenTheRouteRejectsTextFormat() async throws {
        let recorder = BodyRecorder()
        let client = ChatGPTClient(model: "gpt-6-sol", accessToken: { "token" }, openStream: { _, body in
            let first = recorder.bodies.withLock { list in
                list.append(body)
                return list.count == 1
            }
            return AsyncThrowingStream { continuation in
                if first {
                    continuation.yield(.error(code: "subscription_sharing_unsupported_capability", message: "text.format"))
                } else {
                    continuation.yield(.textDelta("{\"items\":"))
                    continuation.yield(.textDelta("[]}"))
                    continuation.yield(.completed)
                }
                continuation.finish()
            }
        })
        #expect(try await client.complete(sampleRequest) == #"{"items":[]}"#)
        let sent = recorder.bodies.withLock { $0 }
        #expect(sent.count == 2)
        #expect(sent[0]["text"] != nil)
        #expect(sent[1]["text"] == nil)
        #expect(sent[1]["stream"] == .bool(true))
        #expect(sent[1]["store"] == .bool(false))
    }
}

// MARK: Error mapping and settings

struct ProviderErrorMappingTests {
    @Test func genericShapes() {
        #expect(AIError.fromProviderHTTP(provider: .openAI, status: 404,
                                         body: #"{"error":{"message":"The model `gpt-9` does not exist","code":"model_not_found"}}"#)
                == .modelNotFound(.openAI, detail: "The model `gpt-9` does not exist"))
        #expect(AIError.fromProviderHTTP(provider: .gemini, status: 429, body: #"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}"#)
                == .rateLimited(.gemini))
        #expect(AIError.fromProviderHTTP(provider: .openAICompatible, status: 502, body: "<html>Bad gateway</html>")
                == .temporarilyUnavailable(.openAICompatible))
        #expect(AIError.fromProviderHTTP(provider: .openAICompatible, status: 402, body: #"{"error":{"message":"Insufficient credits"}}"#)
                == .quotaExceeded(.openAICompatible))
    }

    @Test func factoryExplainsMissingSetup() {
        #expect(throws: AIError.missingKey(.anthropic)) {
            try LLMClientFactory.make(ProviderConfig(kind: .anthropic, model: "claude-opus-5-5", apiKey: "  "))
        }
        #expect(throws: AIError.noModel(.gemini)) {
            try LLMClientFactory.make(ProviderConfig(kind: .gemini, model: "", apiKey: "k"))
        }
        #expect(throws: AIError.missingServer) {
            try LLMClientFactory.make(ProviderConfig(kind: .openAICompatible, model: "llama", apiKey: nil, baseURL: nil))
        }
        #expect((try? LLMClientFactory.make(ProviderConfig(kind: .openAICompatible, model: "llama", apiKey: nil,
                                                            baseURL: URL(string: "http://10.0.0.2:1234/v1")))) != nil)
    }

    @Test func keysAreMasked() {
        #expect(APIKeyStore.masked("sk-ant-api03-abcdefghijklmnop-WXYZ") == "sk-…WXYZ")
        #expect(APIKeyStore.masked("short") == "••••••••")
    }

    @Test func everyKeyedProviderHasASuggestedModelAndKeyPage() {
        for kind in [ProviderKind.anthropic, .openAI, .gemini] {
            #expect(kind.suggestedModel?.isEmpty == false)
            #expect(kind.keyPageURL != nil)
        }
        #expect(!ProviderKind.openAICompatible.requiresAPIKey)
        #expect(!ProviderKind.chatGPT.usesAPIKey)
    }
}

// MARK: Estimator

struct FoodEstimatorTests {
    private func estimator(_ client: ScriptedClient) -> FoodEstimator {
        FoodEstimator(client: client, sleep: { _ in })
    }

    @Test func sendsImageTextSchemaAndPrompt() async throws {
        let client = ScriptedClient([.reply(goodEstimate)])
        let estimate = try await estimator(client).estimate(description: "two eggs", jpeg: Data([1, 2, 3]))
        #expect(estimate.items.first?.name == "Fried egg")
        #expect(estimate.analysis == "Two fried eggs.")
        let request = try #require(client.requests.first)
        #expect(request.schema?.name == "food_estimate")
        #expect(request.system == FoodPrompt.system)
        #expect(request.messages.first?.parts == [.image(Data([1, 2, 3]), mimeType: "image/jpeg"),
                                                  .text("What I ate (see the photo): two eggs")])
    }

    @Test func repairsAnUnreadableAnswerOnce() async throws {
        let client = ScriptedClient([.reply("Sure! Here are your items: eggs"), .reply(goodEstimate)])
        let estimate = try await estimator(client).estimate(description: "two eggs", jpeg: nil)
        #expect(estimate.items.count == 1)
        let second = try #require(client.requests.last)
        #expect(second.messages.count == 3)
        #expect(second.messages[1] == .assistant("Sure! Here are your items: eggs"))
        #expect(second.messages[2].role == .user)
    }

    @Test func impossibleNumbersAreSentBackThenReported() async throws {
        let impossible = #"{"analysis":"","items":[{"name":"Butter","grams":10,"kcal":500,"protein_g":0,"carbs_g":0,"fat_g":9,"confidence":"low","source":"estimate"}],"note":""}"#
        let client = ScriptedClient([.reply(impossible), .reply(impossible)])
        await #expect(throws: AIError.implausible("Butter has 50.0 kcal per gram, more than pure fat")) {
            try await estimator(client).estimate(description: "butter", jpeg: nil)
        }
        #expect(client.requests.count == 2)
        guard case .some(.text(let repair)) = client.requests[1].messages[2].parts.first else {
            Issue.record("expected a text repair message")
            return
        }
        #expect(repair.contains("more than pure fat"))
    }

    @Test func retriesTransientErrorsButNotKeyErrors() async throws {
        let flaky = ScriptedClient([.fail(.temporarilyUnavailable(.anthropic)), .fail(.rateLimited(.anthropic)), .reply(goodEstimate)])
        #expect(try await estimator(flaky).estimate(description: "eggs", jpeg: nil).items.count == 1)
        #expect(flaky.requests.count == 3)

        let badKey = ScriptedClient([.fail(.invalidKey(.anthropic)), .reply(goodEstimate)])
        await #expect(throws: AIError.invalidKey(.anthropic)) {
            try await estimator(badKey).estimate(description: "eggs", jpeg: nil)
        }
        #expect(badKey.requests.count == 1)

        let down = ScriptedClient([.fail(.temporarilyUnavailable(.anthropic)), .fail(.temporarilyUnavailable(.anthropic)),
                                   .fail(.temporarilyUnavailable(.anthropic)), .reply(goodEstimate)])
        await #expect(throws: AIError.temporarilyUnavailable(.anthropic)) {
            try await estimator(down).estimate(description: "eggs", jpeg: nil)
        }
        #expect(down.requests.count == 3)
    }

    @Test func emptyItemsAreNothingFound() async throws {
        let client = ScriptedClient([.reply(#"{"analysis":"A cat.","items":[],"note":"No food in the photo."}"#)])
        await #expect(throws: AIError.nothingFound("No food in the photo.")) {
            try await estimator(client).estimate(description: nil, jpeg: Data([1]))
        }
    }
}

struct EstimateValidatorTests {
    private func item(_ name: String, grams: Double, kcal: Double, p: Double, c: Double, f: Double) -> EstimatedItem {
        EstimatedItem(name: name, grams: grams, macros: Macros(kcal: kcal, protein: p, carbs: c, fat: f),
                      confidence: .medium, fromLabel: false)
    }

    @Test func realisticMealPasses() {
        let result = EstimateValidator.check(FoodEstimate(items: [
            item("Rice", grams: 200, kcal: 260, p: 5.4, c: 57, f: 0.6),
            item("Olive oil", grams: 10, kcal: 88, p: 0, c: 0, f: 10),
        ]))
        #expect(result == .init(hardProblems: [], warnings: []))
    }

    @Test func macrosHeavierThanFoodIsHard() {
        let result = EstimateValidator.check(FoodEstimate(items: [item("Salad", grams: 50, kcal: 300, p: 20, c: 30, f: 10)]))
        #expect(result.hardProblems == ["Salad's protein, carbs and fat weigh more than the item"])
    }

    @Test func atwaterMismatchIsOnlyAWarning() {
        let result = EstimateValidator.check(FoodEstimate(items: [item("Pasta", grams: 250, kcal: 700, p: 12, c: 75, f: 2)]))
        #expect(result.hardProblems.isEmpty)
        #expect(result.warnings.count == 1)
    }

    @Test func absurdValuesDoNotCrash() {
        let result = EstimateValidator.check(FoodEstimate(items: [item("X", grams: 1e300, kcal: 1e300, p: 0, c: 0, f: 0)]))
        #expect(result.hardProblems.count >= 2)
    }
}

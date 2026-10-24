import Foundation

/// The user's ChatGPT plan through Sign in with ChatGPT: Responses API, streaming only, `store: false`.
struct ChatGPTClient: LLMClient {
    typealias StreamFactory = @Sendable (_ accessToken: String, _ body: JSONValue)
        -> AsyncThrowingStream<ResponsesStreamEvent, Error>

    let model: String
    var accessToken: @Sendable () async throws -> String = { try await ChatGPTClient.sessionAccessToken() }
    var openStream: StreamFactory = { ResponsesClient(accessToken: $0).stream(body: $1) }

    var provider: ProviderKind { .chatGPT }

    func complete(_ request: LLMRequest) async throws -> String {
        let token = try await accessToken()
        do {
            return try await send(request, token: token, useSchema: request.schema != nil)
        } catch let error where request.schema != nil && SchemaFallback.isRejection(error, mentioning: ["text.format", "json_schema"]) {
            // Schema-constrained output on this route is unconfirmed (open question 6); fall back to the prompt alone.
            return try await send(request, token: token, useSchema: false)
        }
    }

    private func send(_ request: LLMRequest, token: String, useSchema: Bool) async throws -> String {
        let body = ResponsesBody.make(model: model, request: request, useSchema: useSchema, stream: true, imageDetail: nil)
        return try await Self.collect(openStream(token, body))
    }

    /// Joins the text deltas. Only `response.completed` counts as success.
    static func collect(_ stream: AsyncThrowingStream<ResponsesStreamEvent, Error>) async throws -> String {
        var text = ""
        do {
            for try await event in stream {
                switch event {
                case .textDelta(let delta): text += delta
                case .completed: return text
                case .failed(let code, let message), .error(let code, let message):
                    throw AIError.fromCode(code, message: message)
                case .incomplete(let reason): throw AIError.incomplete(reason ?? "unknown")
                case .other: continue
                }
            }
        } catch let error as ResponsesClient.HTTPError {
            throw AIError.fromHTTP(status: error.status, body: error.body)
        } catch let error as URLError {
            throw AIError.from(error)
        }
        throw AIError.incomplete("connection closed early")
    }

    static func sessionAccessToken() async throws -> String {
        do {
            return try await AuthSession.shared.validAccessToken()
        } catch AuthSession.AuthError.signedOut {
            throw AIError.notConnected
        } catch AuthSession.AuthError.sessionEnded {
            throw AIError.sessionEnded
        }
    }

    func listModels() async throws -> [LLMModel] {
        let client = ResponsesClient(accessToken: try await accessToken())
        do {
            return try await client.listModels().map { LLMModel(id: $0.slug, displayName: $0.display_name) }
        } catch let error as ResponsesClient.HTTPError {
            throw AIError.fromHTTP(status: error.status, body: error.body)
        }
    }
}

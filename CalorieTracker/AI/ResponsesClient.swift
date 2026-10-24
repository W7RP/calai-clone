import Foundation

/// Minimal client for `POST /v1/responses` on the Sign in with ChatGPT route: always `store: false`, `stream: true`.
struct ResponsesClient: Sendable {
    let accessToken: String
    private let base = URL(string: "https://api.openai.com/v1")!

    struct HTTPError: LocalizedError {
        let status: Int
        let body: String
        var errorDescription: String? { "HTTP \(status): \(body)" }
    }

    struct Model: Decodable, Identifiable, Hashable, Sendable {
        let slug: String
        let display_name: String?
        let visibility: String?
        var id: String { slug }
    }

    func listModels() async throws -> [Model] {
        struct Listing: Decodable { let models: [Model] }
        var request = URLRequest(url: base.appending(path: "models"))
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        return try JSONDecoder().decode(Listing.self, from: data).models.filter { $0.visibility == "list" }
    }

    enum Part: Encodable, Sendable {
        case text(String)
        case jpeg(Data)

        private enum CodingKeys: String, CodingKey { case type, text, image_url }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try c.encode("input_text", forKey: .type)
                try c.encode(text, forKey: .text)
            case .jpeg(let data):
                try c.encode("input_image", forKey: .type)
                try c.encode("data:image/jpeg;base64,\(data.base64EncodedString())", forKey: .image_url)
            }
        }
    }

    /// Streams events until the response finishes. The caller decides what counts as success:
    /// only `.completed` does, per the docs.
    func stream(model: String, instructions: String, parts: [Part]) -> AsyncThrowingStream<ResponsesStreamEvent, Error> {
        struct Message: Encodable { let role = "user"; let content: [Part] }
        struct Body: Encodable {
            let model: String
            let instructions: String
            let input: [Message]
            let store = false
            let stream = true
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: base.appending(path: "responses"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    authorize(&request)
                    request.httpBody = try JSONEncoder().encode(
                        Body(model: model, instructions: instructions, input: [Message(content: parts)]))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = Data()
                        for try await byte in bytes where body.count < 1_000 { body.append(byte) }
                        throw HTTPError(status: http.statusCode, body: String(decoding: body, as: UTF8.self))
                    }
                    for try await line in bytes.lines {
                        if let event = ResponsesStreamEvent.parse(line: line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    private func check(_ response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HTTPError(status: status, body: String(decoding: data.prefix(1_000), as: UTF8.self)) }
    }
}

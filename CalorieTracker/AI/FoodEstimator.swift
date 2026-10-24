import Foundation

/// Turns a photo and/or a description into reviewable items using the user's ChatGPT plan.
struct FoodEstimator: Sendable {
    static let modelKey = "aiModel"

    static let instructions = """
    You estimate nutrition for a personal calorie tracker. Reply with one JSON object and nothing else:
    {"items":[{"name":string,"grams":number,"kcal":number,"protein_g":number,"carbs_g":number,"fat_g":number,\
    "confidence":"high"|"medium"|"low","source":"label"|"estimate"}],"note":string|null}
    Rules:
    - Metric units. Numbers are for the portion eaten, not per 100 g.
    - If a nutrition facts label is visible, read the printed values and scale them to the portion; set source "label".
    - Otherwise estimate a realistic portion and set confidence honestly; use "low" when guessing.
    - Split a meal into separate items (e.g. "2 eggs", "toast", "butter").
    - Products are often from Canadian (Quebec) grocery stores; labels may be in French.
    - If nothing edible is identifiable, return {"items":[],"note":"<short reason>"}.
    """

    func estimate(description: String?, jpeg: Data?) async throws -> FoodEstimate {
        guard let model = UserDefaults.standard.string(forKey: Self.modelKey), !model.isEmpty else { throw AIError.noModel }
        let token: String
        do {
            token = try await AuthSession.shared.validAccessToken()
        } catch AuthSession.AuthError.signedOut {
            throw AIError.notConnected
        } catch AuthSession.AuthError.sessionEnded {
            throw AIError.sessionEnded
        }

        var parts: [ResponsesClient.Part] = []
        let text = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        parts.append(.text(text.isEmpty ? "What did I eat? Estimate each item." : text))
        if let jpeg { parts.append(.jpeg(jpeg)) }

        let output = try await collect(ResponsesClient(accessToken: token).stream(
            model: model, instructions: Self.instructions, parts: parts))
        let estimate = try FoodEstimateParser.parse(output)
        if estimate.items.isEmpty { throw AIError.nothingFound(estimate.note) }
        return estimate
    }

    /// Joins the text deltas. Only `response.completed` counts as success.
    private func collect(_ stream: AsyncThrowingStream<ResponsesStreamEvent, Error>) async throws -> String {
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
        }
        throw AIError.incomplete("connection closed early")
    }
}

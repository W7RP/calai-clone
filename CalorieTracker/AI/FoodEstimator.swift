import Foundation

/// Turns a photo and/or a description into reviewable items with whichever provider is set up.
/// Retries transient failures with backoff, and asks the model once more when its answer can't be used.
struct FoodEstimator: Sendable {
    let client: any LLMClient
    /// Pause before retrying a transient error. Replaced in tests.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var maxTransientRetries = 2
    var maxRepairs = 1

    /// The estimator for the provider chosen in Settings.
    static func current() throws -> FoodEstimator {
        FoodEstimator(client: try LLMClientFactory.make(AIProviderSettings.config(for: AIProviderSettings.activeProvider)))
    }

    func estimate(description: String?, jpeg: Data?) async throws -> FoodEstimate {
        var first = LLMMessage(role: .user, parts: [])
        if let jpeg { first.parts.append(.image(jpeg, mimeType: "image/jpeg")) }
        first.parts.append(.text(FoodPrompt.userText(description: description, hasImage: jpeg != nil)))
        var request = LLMRequest(system: FoodPrompt.system, messages: [first], schema: FoodPrompt.schema)

        var repairsLeft = maxRepairs
        while true {
            let output = try await completeWithRetry(request)
            let problem: String
            do {
                var estimate = try FoodEstimateParser.parse(output)
                let check = EstimateValidator.check(estimate)
                if check.hardProblems.isEmpty {
                    if estimate.items.isEmpty { throw AIError.nothingFound(estimate.note) }
                    estimate.warnings = check.warnings
                    return estimate
                }
                guard repairsLeft > 0 else { throw AIError.implausible(check.hardProblems.joined(separator: "; ")) }
                problem = check.hardProblems.joined(separator: "; ")
            } catch AIError.unreadable where repairsLeft > 0 {
                problem = "it was not a valid JSON object in the required shape"
            }
            repairsLeft -= 1
            // Keep the original photo and text, add the bad answer and what was wrong with it.
            request.messages = [first, .assistant(String(output.prefix(4_000))), .user(.text(FoodPrompt.repair(problem: problem)))]
        }
    }

    private func completeWithRetry(_ request: LLMRequest) async throws -> String {
        var attempt = 0
        while true {
            do {
                return try await client.complete(request)
            } catch let error as AIError where error.isTransient && attempt < maxTransientRetries && !Task.isCancelled {
                attempt += 1
                try await sleep(.milliseconds(attempt == 1 ? 1_500 : 4_000))
            } catch let error as AIError where error.isIncomplete && attempt == 0 {
                // Usually a one-off (stream cut, long thinking); one plain retry.
                attempt += 1
            }
        }
    }
}

private extension AIError {
    var isIncomplete: Bool {
        if case .incomplete = self { true } else { false }
    }
}

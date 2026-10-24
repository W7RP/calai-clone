import Foundation

/// One conversation with the coach. Kept in memory for as long as the app runs; nothing is saved.
@MainActor
@Observable
final class CoachSession {
    struct Message: Identifiable, Equatable {
        enum Role { case user, coach }
        let id = UUID()
        let role: Role
        let text: String
    }

    private(set) var messages: [Message] = []
    private(set) var isThinking = false
    private(set) var error: String?

    /// Older turns are dropped past this, so long chats stay fast and cheap.
    static let historyLimit = 12

    private var task: Task<Void, Never>?
    /// Builds the client for each question. Replaced in tests.
    var makeClient: @MainActor () throws -> any LLMClient = {
        try LLMClientFactory.make(AIProviderSettings.config(for: AIProviderSettings.activeProvider))
    }

    func ask(_ question: String, context: CoachContext) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        messages.append(Message(role: .user, text: question))
        error = nil
        isThinking = true
        let request = Self.request(for: messages, context: context)
        task = Task { [self] in
            do {
                let reply = try await makeClient().complete(request)
                guard !Task.isCancelled else { return }
                isThinking = false
                let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                messages.append(Message(role: .coach, text: text.isEmpty ? "Sorry, I didn't get an answer. Try asking again." : text))
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                isThinking = false
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Asks the last question again after an error.
    func retry(context: CoachContext) {
        guard let last = messages.last, last.role == .user else { return }
        messages.removeLast()
        ask(last.text, context: context)
    }

    func reset() {
        task?.cancel()
        task = nil
        messages = []
        error = nil
        isThinking = false
    }

    nonisolated static func request(for messages: [Message], context: CoachContext) -> LLMRequest {
        var recent = Array(messages.suffix(historyLimit))
        // Providers want the conversation to start with the user.
        while recent.first?.role == .coach { recent.removeFirst() }
        return LLMRequest(system: CoachPrompt.system(context),
                          messages: recent.map { $0.role == .user ? .user(.text($0.text)) : .assistant($0.text) },
                          maxOutputTokens: 4_000)
    }
}

import Foundation

enum LLMClientFactory {
    /// Builds a client, or explains what's missing from the setup.
    /// `requireModel` is false when only listing models, which doesn't need one picked yet.
    static func make(_ config: ProviderConfig, requireModel: Bool = true,
                     transport: any HTTPTransport = URLSessionTransport()) throws -> any LLMClient {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if requireModel, model.isEmpty { throw AIError.noModel(config.kind) }
        let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if config.kind.requiresAPIKey, key.isEmpty { throw AIError.missingKey(config.kind) }

        switch config.kind {
        case .chatGPT:
            return ChatGPTClient(model: model)
        case .anthropic:
            return AnthropicClient(apiKey: key, model: model, transport: transport)
        case .openAI:
            return OpenAIClient(apiKey: key, model: model, transport: transport)
        case .gemini:
            return GeminiClient(apiKey: key, model: model, transport: transport)
        case .openAICompatible:
            guard let baseURL = config.baseURL else { throw AIError.missingServer }
            return OpenAICompatibleClient(baseURL: baseURL, apiKey: key.isEmpty ? nil : key, model: model, transport: transport)
        }
    }
}

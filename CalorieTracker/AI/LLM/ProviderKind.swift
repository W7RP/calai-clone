import Foundation

/// The AI services the app can use. The user brings their own account or key; nothing is bundled.
enum ProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case chatGPT
    case anthropic
    case openAI
    case gemini
    case openAICompatible

    var id: String { rawValue }

    /// Short name for messages and buttons ("Asking Claude…").
    var name: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .anthropic: "Claude"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .openAICompatible: "Custom server"
        }
    }

    /// Longer label for the provider picker.
    var pickerTitle: String {
        switch self {
        case .chatGPT: "ChatGPT plan (sign in)"
        case .anthropic: "Claude (Anthropic API key)"
        case .openAI: "OpenAI (API key)"
        case .gemini: "Google Gemini (API key)"
        case .openAICompatible: "OpenAI-compatible server"
        }
    }

    var summary: String {
        switch self {
        case .chatGPT: "Uses your ChatGPT Plus/Pro/Go allowance. No API billing."
        case .anthropic: "Pay-as-you-go on your Anthropic account."
        case .openAI: "Pay-as-you-go on your OpenAI Platform account."
        case .gemini: "Google AI Studio key. Has a free tier with rate limits."
        case .openAICompatible: "OpenRouter, Ollama, LM Studio, vLLM, Groq and other servers with a /chat/completions endpoint."
        }
    }

    var usesAPIKey: Bool { self != .chatGPT }
    /// A local server usually has no key.
    var requiresAPIKey: Bool { usesAPIKey && self != .openAICompatible }

    /// Where to create a key.
    var keyPageURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .chatGPT, .openAICompatible: nil
        }
    }

    /// Starting point only; Settings can list what the account actually has. Checked 2026-10-24.
    var suggestedModel: String? {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openAI: "gpt-6-sol"
        case .gemini: "gemini-3.8-flash"
        case .chatGPT, .openAICompatible: nil
        }
    }
}

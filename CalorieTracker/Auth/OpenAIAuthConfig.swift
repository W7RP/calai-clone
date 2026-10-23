import Foundation

/// Values from docs/openai-signin.md. Sign in with ChatGPT is in preview; re-check the docs if anything here starts failing.
enum OpenAIAuthConfig {
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let registrationClientID = "dynamic_agent_client"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let requiredScope = "chatgpt.tokens.use.direct"
    static let agentName = "Calorie Tracker"

    // Scheme, host and path must never change between sign-ins; only the port may.
    static let callbackPath = "/auth/callback"
    static let preferredPort: UInt16 = 1455

    static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(callbackPath)"
    }

    static func authorizeRequestURL(attempt: AuthAttempt, redirectURI: String, hostID: String,
                                    issuedClientID: String?) -> URL {
        var items = [
            URLQueryItem(name: "client_id", value: issuedClientID ?? registrationClientID),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "nonce", value: attempt.nonce),
            URLQueryItem(name: "code_challenge", value: attempt.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        // The docs say to send the name hint only when registering, not when reusing an issued client ID.
        if issuedClientID == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: agentName))
        }
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        // URLComponents leaves "+" and spaces in a form some servers misread; encode them strictly.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

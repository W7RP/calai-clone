import Foundation

/// Owns the token set. An actor so a later refresh can't race another request using a rotating refresh token.
actor AuthSession {
    enum AuthError: LocalizedError {
        case stateMismatch
        case denied
        case missingCode
        case clientIDMismatch
        case tokenExchange(status: Int, body: String)
        case idToken(String)
        case missingScope([String])

        var errorDescription: String? {
            switch self {
            case .stateMismatch: "The sign-in response didn't match this attempt (state mismatch)."
            case .denied: "Sign-in was declined."
            case .missingCode: "The sign-in response had no authorization code."
            case .clientIDMismatch: "The sign-in response came back for a different app registration."
            case .tokenExchange(let status, let body): "Token exchange failed (HTTP \(status)): \(body)"
            case .idToken(let reason): "ID token check failed: \(reason)"
            case .missingScope(let granted): "Plan usage wasn't granted. Scopes: \(granted.joined(separator: " "))"
            }
        }
    }

    private(set) var tokens: TokenSet?

    init() {
        tokens = TokenStore.load()
    }

    /// Stable per install, as `ext_agent_host_id` requires.
    nonisolated static var hostID: String {
        let key = "extAgentHostID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    func authorizeURL(attempt: AuthAttempt, redirectURI: String) -> URL {
        OpenAIAuthConfig.authorizeRequestURL(attempt: attempt, redirectURI: redirectURI,
                                             hostID: Self.hostID, issuedClientID: tokens?.issuedClientID)
    }

    func complete(callback: AuthCallback, attempt: AuthAttempt, redirectURI: String) async throws {
        guard callback.state == attempt.state else { throw AuthError.stateMismatch }
        if callback.error == "access_denied" { throw AuthError.denied }
        guard let code = callback.code else { throw AuthError.missingCode }

        let saved = tokens?.issuedClientID
        if let saved, let returned = callback.issuedClientID, returned != saved { throw AuthError.clientIDMismatch }
        guard let clientID = callback.issuedClientID ?? saved else { throw AuthError.missingCode }

        let response = try await exchange(code: code, clientID: clientID, verifier: attempt.verifier, redirectURI: redirectURI)
        let scopes = (response.scope ?? "").split(separator: " ").map(String.init)
        guard scopes.contains(OpenAIAuthConfig.requiredScope) else { throw AuthError.missingScope(scopes) }

        var subject: String?
        if let idToken = response.id_token {
            subject = try IDTokenClaims.check(idToken, clientID: clientID, nonce: attempt.nonce)
        }

        let set = TokenSet(issuedClientID: clientID,
                           accessToken: response.access_token,
                           refreshToken: response.refresh_token,
                           idToken: response.id_token,
                           expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)),
                           grantedScopes: scopes,
                           accountSubject: subject,
                           redirectURI: redirectURI)
        try TokenStore.save(set)
        tokens = set
    }

    func signOut() {
        TokenStore.delete()
        tokens = nil
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let id_token: String?
        let expires_in: Int?
        let scope: String?
    }

    private func exchange(code: String, clientID: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        var request = URLRequest(url: OpenAIAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "resource": OpenAIAuthConfig.resource,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // Error bodies carry an error code and description, never tokens, so they're safe to show.
            throw AuthError.tokenExchange(status: status, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

enum FormEncoding {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ fields: [String: String]) -> Data {
        let body = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

/// Claim checks on the ID token. Spike only: the signature isn't verified yet because the docs pages
/// checked so far don't name the JWKS URL. Phase 3 adds signature verification before relying on `sub`.
enum IDTokenClaims {
    static func check(_ jwt: String, clientID: String, nonce: String, now: Date = Date()) throws -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3,
              let data = Data(base64URLEncoded: String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthSession.AuthError.idToken("malformed")
        }
        guard claims["iss"] as? String == OpenAIAuthConfig.issuer else {
            throw AuthSession.AuthError.idToken("unexpected issuer")
        }
        let audiences = (claims["aud"] as? [String]) ?? [(claims["aud"] as? String)].compactMap { $0 }
        guard audiences.contains(clientID) else { throw AuthSession.AuthError.idToken("audience mismatch") }
        guard let exp = claims["exp"] as? Double, Date(timeIntervalSince1970: exp) > now else {
            throw AuthSession.AuthError.idToken("expired")
        }
        guard claims["nonce"] as? String == nonce else { throw AuthSession.AuthError.idToken("nonce mismatch") }
        return claims["sub"] as? String
    }
}

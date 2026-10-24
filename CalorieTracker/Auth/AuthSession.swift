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
        case signedOut
        case sessionEnded
        case refresh(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .stateMismatch: "The sign-in response didn't match this attempt (state mismatch)."
            case .denied: "Sign-in was declined."
            case .missingCode: "The sign-in response had no authorization code."
            case .clientIDMismatch: "The sign-in response came back for a different app registration."
            case .tokenExchange(let status, let body): "Token exchange failed (HTTP \(status)): \(body)"
            case .idToken(let reason): "ID token check failed: \(reason)"
            case .missingScope(let granted): "Plan usage wasn't granted. Scopes: \(granted.joined(separator: " "))"
            case .signedOut: "Connect your ChatGPT account in Settings to use AI logging."
            case .sessionEnded: "Your ChatGPT session ended. Connect again in Settings."
            case .refresh(let status, _): "Couldn't renew the ChatGPT session (HTTP \(status)). Try again shortly."
            }
        }
    }

    static let shared = AuthSession()

    private(set) var tokens: TokenSet?
    private var refreshTask: Task<TokenSet, Error>?

    private init() {
        tokens = TokenStore.load()
    }

    private static let clientIDKey = "openaiIssuedClientID"

    /// The issued `oaiapp_...` ID outlives sign-out, so signing in again reuses the registration. Not a secret.
    nonisolated static var savedClientID: String? {
        get { UserDefaults.standard.string(forKey: clientIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: clientIDKey) }
    }

    func authorizeURL(attempt: AuthAttempt, redirectURI: String) -> URL {
        OpenAIAuthConfig.authorizeRequestURL(attempt: attempt, redirectURI: redirectURI,
                                             issuedClientID: tokens?.issuedClientID ?? Self.savedClientID)
    }

    func complete(callback: AuthCallback, attempt: AuthAttempt, redirectURI: String) async throws {
        guard callback.state == attempt.state else { throw AuthError.stateMismatch }
        if callback.error == "access_denied" { throw AuthError.denied }
        guard let code = callback.code else { throw AuthError.missingCode }

        let saved = tokens?.issuedClientID ?? Self.savedClientID
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
        Self.savedClientID = clientID
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        TokenStore.delete()
        tokens = nil
    }

    /// A usable access token, refreshing first when it's within two minutes of expiry.
    /// Concurrent callers share one refresh, because the refresh token rotates on every use.
    func validAccessToken(now: Date = Date()) async throws -> String {
        guard let current = tokens else { throw AuthError.signedOut }
        if current.expiresAt.timeIntervalSince(now) > 120 { return current.accessToken }
        guard let refreshToken = current.refreshToken else {
            endSession()
            throw AuthError.sessionEnded
        }

        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { try await Self.refresh(current, refreshToken: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let renewed = try await task.value
            try TokenStore.save(renewed)
            tokens = renewed
            return renewed.accessToken
        } catch AuthError.sessionEnded {
            endSession()
            throw AuthError.sessionEnded
        }
    }

    /// Called when a request confirms the credentials are dead (not on network errors).
    func endSession() {
        TokenStore.delete()
        tokens = nil
    }

    private static let terminalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused",
    ]

    private static func refresh(_ current: TokenSet, refreshToken: String) async throws -> TokenSet {
        var request = URLRequest(url: OpenAIAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Omitting `scope` keeps the existing grant.
        request.httpBody = FormEncoding.encode([
            "grant_type": "refresh_token",
            "client_id": current.issuedClientID,
            "refresh_token": refreshToken,
            "resource": OpenAIAuthConfig.resource,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let code = json?["error"] as? String, terminalRefreshErrors.contains(code) { throw AuthError.sessionEnded }
            throw AuthError.refresh(status: status, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        var renewed = current
        // Access token, expiry, scopes and the rotated refresh token are replaced together.
        renewed.accessToken = body.access_token
        renewed.refreshToken = body.refresh_token ?? refreshToken
        renewed.expiresAt = Date().addingTimeInterval(TimeInterval(body.expires_in ?? 3600))
        if let scope = body.scope {
            renewed.grantedScopes = scope.split(separator: " ").map(String.init)
        }
        if let idToken = body.id_token { renewed.idToken = idToken }
        return renewed
    }

    struct TokenResponse: Decodable {
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

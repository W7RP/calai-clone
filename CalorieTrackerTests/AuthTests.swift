import Foundation
import Testing
@testable import CalorieTracker

struct PKCETests {
    @Test func challengeIsBase64URLSHA256() {
        // Expected value computed independently with Python's hashlib + urlsafe_b64encode.
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mJ92K1g8Ka8IQK2yWG7-Zs5-HmzrOU") == "f33vxu66KY1d5lP3iMxpu5vzQcet0kRsv1Xu8M0OAoE")
    }

    @Test func randomValuesAreURLSafeAndUnique() {
        let a = PKCE.randomURLSafe(byteCount: 32)
        let b = PKCE.randomURLSafe(byteCount: 32)
        #expect(a != b)
        #expect(a.count == 43)
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func base64URLRoundTrips() {
        let data = Data([0xFB, 0xFF, 0xBF, 0x00, 0x01])
        #expect(Data(base64URLEncoded: data.base64URLEncoded()) == data)
    }
}

struct AuthorizeURLTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func firstSignInRegistersDynamically() {
        let attempt = AuthAttempt.make()
        let url = OpenAIAuthConfig.authorizeRequestURL(attempt: attempt, redirectURI: "http://127.0.0.1:1455/auth/callback",
                                                       issuedClientID: nil)
        let q = query(url)
        #expect(q["client_id"] == "dynamic_agent_client")
        #expect(q["agent_name_hint"] == OpenAIAuthConfig.agentName)
        #expect(q["redirect_uri"] == "http://127.0.0.1:1455/auth/callback")
        #expect(q["code_challenge"] == attempt.challenge)
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["scope"] == OpenAIAuthConfig.scopes)
        #expect(q["ext_agent_host_id"] == nil)
    }

    @Test func reauthorizationReusesIssuedClientAndDropsNameHint() {
        let url = OpenAIAuthConfig.authorizeRequestURL(attempt: .make(), redirectURI: "http://127.0.0.1:1455/auth/callback",
                                                       issuedClientID: "oaiapp_abc")
        let q = query(url)
        #expect(q["client_id"] == "oaiapp_abc")
        #expect(q["agent_name_hint"] == nil)
    }
}

struct AuthCallbackTests {
    @Test func parsesListenerURL() {
        let cb = AuthCallback(url: URL(string: "http://127.0.0.1:1455/auth/callback?code=c1&state=s1&client_id=oaiapp_x")!)
        #expect(cb.code == "c1")
        #expect(cb.state == "s1")
        #expect(cb.issuedClientID == "oaiapp_x")
        #expect(cb.error == nil)
    }

    @Test func acceptsPastedFullURLWithWhitespace() {
        let cb = AuthCallback(pasted: "  http://127.0.0.1:1455/auth/callback?code=c2&state=s2\n")
        #expect(cb?.code == "c2")
    }

    @Test func rejectsWrongPath() {
        #expect(AuthCallback(pasted: "http://127.0.0.1:1455/callback?code=c") == nil)
    }

    @Test func requestTargetFromRawHTTP() {
        let raw = Data("GET /auth/callback?code=a&state=b HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        #expect(LoopbackListener.requestTarget(fromRequest: raw) == "/auth/callback?code=a&state=b")
        #expect(LoopbackListener.requestTarget(fromRequest: Data("POST / HTTP/1.1\r\n".utf8)) == nil)
    }
}

struct FormEncodingTests {
    @Test func encodesReservedCharacters() {
        let body = String(decoding: FormEncoding.encode(["redirect_uri": "http://127.0.0.1:1455/auth/callback", "a": "x y+z"]), as: UTF8.self)
        #expect(body == "a=x%20y%2Bz&redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback")
    }
}

struct IDTokenClaimsTests {
    private func jwt(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        return "e30.\(payload.base64URLEncoded()).sig"
    }

    private var valid: [String: Any] {
        ["iss": "https://auth.openai.com", "aud": "oaiapp_x", "exp": Date().addingTimeInterval(600).timeIntervalSince1970,
         "nonce": "n1", "sub": "user-123"]
    }

    @Test func acceptsValidClaims() throws {
        #expect(try IDTokenClaims.check(jwt(valid), clientID: "oaiapp_x", nonce: "n1") == "user-123")
    }

    @Test func acceptsAudienceArray() throws {
        var claims = valid
        claims["aud"] = ["other", "oaiapp_x"]
        #expect(try IDTokenClaims.check(jwt(claims), clientID: "oaiapp_x", nonce: "n1") == "user-123")
    }

    @Test func rejectsNonceMismatch() {
        #expect(throws: (any Error).self) { try IDTokenClaims.check(jwt(valid), clientID: "oaiapp_x", nonce: "other") }
    }

    @Test func rejectsExpired() {
        var claims = valid
        claims["exp"] = Date().addingTimeInterval(-10).timeIntervalSince1970
        #expect(throws: (any Error).self) { try IDTokenClaims.check(jwt(claims), clientID: "oaiapp_x", nonce: "n1") }
    }

    @Test func rejectsWrongAudience() {
        #expect(throws: (any Error).self) { try IDTokenClaims.check(jwt(valid), clientID: "oaiapp_other", nonce: "n1") }
    }
}

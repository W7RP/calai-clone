import CryptoKit
import Foundation

/// One sign-in attempt's secrets. A fresh one is made per attempt and never stored.
struct AuthAttempt: Sendable {
    let verifier: String
    let state: String
    let nonce: String

    var challenge: String { PKCE.challenge(for: verifier) }

    static func make() -> AuthAttempt {
        AuthAttempt(verifier: PKCE.randomURLSafe(byteCount: 32),
                    state: PKCE.randomURLSafe(byteCount: 16),
                    nonce: PKCE.randomURLSafe(byteCount: 16))
    }
}

enum PKCE {
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64URLEncoded()
    }
}

extension Data {
    /// RFC 4648 base64url without padding, as PKCE and JWTs use.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s)
    }
}

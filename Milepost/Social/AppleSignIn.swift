import AuthenticationServices
import CryptoKit
import Foundation

/// Nonce plumbing for Sign in with Apple. Apple signs SHA-256(nonce) into the
/// token; Supabase gets the raw nonce and hashes it for comparison. Sending the
/// same form to both fails as a flat "invalid token".
enum AuthNonce {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "secure RNG unavailable")
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum IDToken {
    /// Reads one string claim out of a JWT without verifying it — used only
    /// to decide whether Apple included the nonce claim at all.
    static func stringClaim(_ name: String, from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard let data = Data(base64Encoded: encoded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[name] as? String, !value.isEmpty else { return nil }
        return value
    }
}

struct AppleCredential {
    let idToken: String
    let rawNonce: String
    let fullName: PersonNameComponents?

    static func from(_ authorization: ASAuthorization, rawNonce: String) throws -> AppleCredential {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            throw SocialError.missingIdentityToken
        }
        return AppleCredential(idToken: token, rawNonce: rawNonce, fullName: credential.fullName)
    }
}

enum SocialError: LocalizedError {
    case missingIdentityToken
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken: return "Apple did not return an identity token. Try again."
        case .notConfigured: return "Friends are not available in this build."
        }
    }
}

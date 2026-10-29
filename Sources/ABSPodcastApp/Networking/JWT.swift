import Foundation

/// Reads claims from a JWT without verifying it. The server verifies; the app only needs
/// the expiry to decide when to refresh ahead of time.
enum JWT {
    private struct Claims: Decodable {
        let exp: Double?
    }

    /// The token's `exp` claim, or nil if the token isn't a readable JWT.
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        // JWTs use unpadded base64url; Foundation wants padded standard base64.
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64),
              let exp = try? JSONDecoder().decode(Claims.self, from: data).exp else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }
}

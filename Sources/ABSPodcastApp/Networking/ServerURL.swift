import Foundation

/// The base address of an Audiobookshelf server, normalised from what the user typed.
///
/// ABS can run under a sub-path (its `RouterBasePath`), so the base may include a
/// path such as `/audiobookshelf`. Every endpoint is resolved relative to it.
struct ServerURL: Codable, Hashable, Sendable {
    let base: URL

    /// Parses user input such as `abs.example.com` or `https://example.com/abs/`.
    ///
    /// A missing scheme becomes `https`. Plain `http` is rejected, because App Transport
    /// Security would block it and the server should be reached over TLS anyway.
    init(parsing input: String) throws(ABSError) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalidServerURL("Enter your server's address.") }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty else {
            throw .invalidServerURL("That doesn't look like a web address.")
        }
        guard components.scheme?.lowercased() == "https" else {
            throw .invalidServerURL("The address must start with https://.")
        }
        // A user:password@ part would otherwise be saved with the account in UserDefaults.
        guard components.user == nil, components.password == nil else {
            throw .invalidServerURL("Leave the username and password out of the address.")
        }

        components.scheme = "https"
        components.host = host.lowercased()
        components.query = nil
        components.fragment = nil
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        guard let url = components.url else {
            throw .invalidServerURL("That doesn't look like a web address.")
        }
        base = url
    }

    /// Resolves an endpoint path such as `api/libraries` against the base, keeping any sub-path.
    func url(for path: String) -> URL {
        base.appending(path: path)
    }

    /// Host and sub-path without the scheme, for display.
    var displayName: String {
        (base.host() ?? "") + base.path()
    }
}

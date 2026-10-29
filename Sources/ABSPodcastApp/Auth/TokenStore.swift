import Foundation
import Security

/// The access and refresh tokens for one signed-in session.
struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

/// Persists the current session's tokens. Abstracted so tests can use an in-memory store.
protocol TokenStore: Sendable {
    func load() throws -> AuthTokens?
    func save(_ tokens: AuthTokens) throws
    func delete() throws
}

/// Stores tokens as one generic-password item in the Keychain.
///
/// The item is readable after the first unlock following a reboot, so background
/// playback can refresh the access token while the phone is locked. It never syncs
/// to iCloud or migrates to another device.
struct KeychainTokenStore: TokenStore {
    let service: String
    private let account = "session-tokens"

    init(service: String = Bundle.main.bundleIdentifier ?? "ABSPodcastApp") {
        self.service = service
    }

    func load() throws -> AuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(AuthTokens.self, from: data)
    }

    /// Replaces the item rather than updating it, so the accessibility attribute always applies,
    /// even to an item an older build created with different settings.
    func save(_ tokens: AuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try delete()

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// A Keychain call failed with the given `OSStatus`.
struct KeychainError: Error, Equatable {
    let status: OSStatus
}

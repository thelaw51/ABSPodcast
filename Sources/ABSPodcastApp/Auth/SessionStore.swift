import Foundation
import Observation

/// Who is signed in, and to which server. Persisted in `UserDefaults`; tokens live in the Keychain.
struct Account: Codable, Equatable, Sendable {
    let server: ServerURL
    let userId: String
    let username: String
}

/// App-wide sign-in state. Views read it from the environment to decide what to show.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case signedOut
        case signedIn(Account)
    }

    private(set) var state: State = .signedOut
    /// The only client for the signed-in account. Every token consumer (player, sync) goes through it.
    private(set) var client: ABSClient?

    @ObservationIgnored private let tokenStore: any TokenStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let urlSession: URLSession
    private static let accountKey = "signedInAccount"

    /// Restores the previous session if both the account record and its tokens survive.
    init(
        tokenStore: any TokenStore = KeychainTokenStore(),
        defaults: UserDefaults = .standard,
        urlSession: URLSession = ABSClient.makeSession()
    ) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.urlSession = urlSession

        if let data = defaults.data(forKey: Self.accountKey),
           let account = try? JSONDecoder().decode(Account.self, from: data),
           (try? tokenStore.load()) != nil {
            client = ABSClient(server: account.server, session: urlSession, tokenStore: tokenStore)
            state = .signedIn(account)
        } else {
            // Keychain items survive an app reinstall but UserDefaults don't. Without an
            // account record the tokens are orphaned, so drop them rather than leave a
            // refresh token on the device for up to 30 days.
            try? tokenStore.delete()
        }
    }

    /// Validates the address, checks the server allows password sign-in, then logs in.
    func signIn(serverAddress: String, username: String, password: String) async throws(ABSError) {
        let server = try ServerURL(parsing: serverAddress)
        let status = try await ABSClient.status(of: server, session: urlSession)
        guard status.authMethods.contains("local") else { throw .passwordLoginDisabled }

        let newClient = ABSClient(server: server, session: urlSession, tokenStore: tokenStore)
        let user = try await newClient.login(
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        )

        let account = Account(server: server, userId: user.id, username: user.username)
        guard let accountData = try? JSONEncoder().encode(account) else { throw .decoding }
        defaults.set(accountData, forKey: Self.accountKey)
        client = newClient
        state = .signedIn(account)
    }

    /// Revokes the session on the server where possible and returns to the sign-in screen.
    func signOut() async {
        await client?.logout()
        resetLocalSession()
    }

    /// Call when a request fails. An expired session sends the user back to sign-in.
    func handle(_ error: ABSError) {
        if error == .sessionExpired {
            try? tokenStore.delete()
            resetLocalSession()
        }
    }

    private func resetLocalSession() {
        defaults.removeObject(forKey: Self.accountKey)
        client = nil
        state = .signedOut
    }
}

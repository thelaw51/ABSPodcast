import Foundation

/// Talks to one Audiobookshelf server on behalf of one signed-in user.
///
/// Access tokens last an hour by default. When a request gets a 401, the client
/// refreshes once and retries. ABS rotates the refresh token on every refresh, so
/// concurrent 401s share a single in-flight refresh instead of each spending the
/// same refresh token.
///
/// Coalescing only works within one instance, so the app must have exactly one client
/// per signed-in account: `SessionStore.client`. A second client reading the same
/// token store would spend the same refresh token and sign the user out.
actor ABSClient {
    let server: ServerURL
    private let session: URLSession
    private let tokenStore: any TokenStore
    private var tokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, Error>?

    /// A session that keeps no cookies or cache on disk and refuses redirects to another host,
    /// so a redirect can't carry the password or refresh token somewhere else.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        return URLSession(configuration: config, delegate: SameHostRedirectPolicy(), delegateQueue: nil)
    }

    init(server: ServerURL, session: URLSession, tokenStore: any TokenStore) {
        self.server = server
        self.session = session
        self.tokenStore = tokenStore
        self.tokens = try? tokenStore.load()
    }

    // MARK: - Unauthenticated

    /// Checks that the address is an ABS server and reports its version and enabled sign-in methods.
    static func status(of server: ServerURL, session: URLSession) async throws(ABSError) -> ServerStatus {
        let request = URLRequest(url: server.url(for: "status"))
        let (data, response) = try await send(request, using: session)
        guard response.statusCode == 200,
              let status = try? JSONDecoder().decode(ServerStatus.self, from: data),
              status.app == "audiobookshelf" else {
            throw .notAudiobookshelf
        }
        return status
    }

    /// Signs in with a username and password and stores the returned tokens.
    ///
    /// `x-return-tokens: true` asks ABS to put the refresh token in the body. Without
    /// it, ABS sets a browser cookie instead, which the app doesn't use.
    func login(username: String, password: String) async throws(ABSError) -> LoginResponse.User {
        var request = URLRequest(url: server.url(for: "login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-return-tokens")
        request.httpBody = try? JSONEncoder().encode(["username": username, "password": password])

        let (data, response) = try await Self.send(request, using: session)
        switch response.statusCode {
        case 200: break
        case 401: throw .invalidCredentials
        case 429: throw .tooManyAttempts
        default: throw .http(status: response.statusCode)
        }

        let user = try Self.decode(LoginResponse.self, from: data).user
        guard let refreshToken = user.refreshToken else { throw .missingRefreshToken }
        let newTokens = AuthTokens(accessToken: user.accessToken, refreshToken: refreshToken)
        do {
            try tokenStore.save(newTokens)
        } catch {
            throw .tokenStorage
        }
        tokens = newTokens
        return user
    }

    // MARK: - Authenticated

    /// The user's podcast libraries in the order the server displays them.
    func podcastLibraries() async throws(ABSError) -> [Library] {
        let response: LibrariesResponse = try await authorizedGet("api/libraries")
        return response.libraries
            .filter(\.isPodcastLibrary)
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    /// Every podcast in a library, sorted by title, with each one's unplayed episode count.
    ///
    /// Omitting `limit` makes ABS return the whole library in one response.
    func podcasts(inLibrary libraryId: String) async throws(ABSError) -> [PodcastSummary] {
        let page: LibraryItemsPage = try await authorizedGet(
            "api/libraries/\(libraryId)/items",
            query: [
                URLQueryItem(name: "sort", value: "media.metadata.title"),
                URLQueryItem(name: "minified", value: "1"),
                URLQueryItem(name: "include", value: "numEpisodesIncomplete")
            ]
        )
        return page.results
    }

    /// One podcast with all of its episodes.
    func podcast(id: String) async throws(ABSError) -> PodcastDetail {
        try await authorizedGet("api/items/\(id)", query: [URLQueryItem(name: "expanded", value: "1")])
    }

    /// Every listening-progress record for the signed-in user, across all libraries.
    func mediaProgress() async throws(ABSError) -> [MediaProgress] {
        let response: MediaProgressResponse = try await authorizedGet("api/me/progress")
        return response.mediaProgress
    }

    /// Cover art URL for a library item, sized for the screen.
    ///
    /// ABS serves covers without auth, so `AsyncImage` and the shared URL cache can load
    /// them directly. Passing `updatedAt` as `ts` makes ABS send a one-day cache header and
    /// changes the URL when the cover changes.
    nonisolated func coverURL(itemId: String, updatedAt: Int64?, width: Int) -> URL {
        var url = server.url(for: "api/items/\(itemId)/cover")
        var query = [URLQueryItem(name: "width", value: String(width)), URLQueryItem(name: "format", value: "jpeg")]
        if let updatedAt { query.append(URLQueryItem(name: "ts", value: String(updatedAt))) }
        url.append(queryItems: query)
        return url
    }

    /// Revokes this device's session on the server, then forgets the tokens locally.
    ///
    /// Local tokens are deleted even if the server can't be reached.
    func logout() async {
        if let refreshToken = tokens?.refreshToken {
            var request = URLRequest(url: server.url(for: "logout"))
            request.httpMethod = "POST"
            request.setValue(refreshToken, forHTTPHeaderField: "x-refresh-token")
            _ = try? await Self.send(request, using: session)
        }
        clearTokens()
    }

    // MARK: - Request plumbing

    private func authorizedGet<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws(ABSError) -> T {
        guard let current = tokens else { throw .sessionExpired }

        var (data, response) = try await Self.send(authorizedRequest(path, query: query, token: current.accessToken), using: session)
        if response.statusCode == 401 {
            let fresh = try await refreshedTokens(replacing: current)
            (data, response) = try await Self.send(authorizedRequest(path, query: query, token: fresh.accessToken), using: session)
        }

        switch response.statusCode {
        case 200: return try Self.decode(T.self, from: data)
        case 401: throw .sessionExpired
        default: throw .http(status: response.statusCode)
        }
    }

    private func authorizedRequest(_ path: String, query: [URLQueryItem], token: String) -> URLRequest {
        var url = server.url(for: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Returns tokens newer than `stale`, refreshing at most once however many callers ask.
    private func refreshedTokens(replacing stale: AuthTokens) async throws(ABSError) -> AuthTokens {
        // Another request already refreshed while this one was waiting on its 401.
        if let current = tokens, current != stale { return current }

        let task: Task<AuthTokens, Error>
        if let refreshTask {
            task = refreshTask
        } else {
            // The task clears itself, so a waiter resuming late can't clear a newer refresh.
            task = Task {
                defer { self.refreshTask = nil }
                return try await self.performRefresh(using: stale.refreshToken)
            }
            refreshTask = task
        }

        do {
            return try await task.value
        } catch {
            throw (error as? ABSError) ?? .sessionExpired
        }
    }

    private func performRefresh(using refreshToken: String) async throws(ABSError) -> AuthTokens {
        var request = URLRequest(url: server.url(for: "auth/refresh"))
        request.httpMethod = "POST"
        request.setValue(refreshToken, forHTTPHeaderField: "x-refresh-token")

        let (data, response) = try await Self.send(request, using: session)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 { clearTokens() }
            throw response.statusCode == 401 ? .sessionExpired : .http(status: response.statusCode)
        }

        let user = try Self.decode(LoginResponse.self, from: data).user
        guard let newRefreshToken = user.refreshToken else { throw .missingRefreshToken }
        let fresh = AuthTokens(accessToken: user.accessToken, refreshToken: newRefreshToken)
        // The old refresh token dies shortly after rotation, so keep the new pair in memory
        // even if the Keychain write fails. The running session survives; only a relaunch
        // would need a new sign-in.
        tokens = fresh
        try? tokenStore.save(fresh)
        return fresh
    }

    private func clearTokens() {
        tokens = nil
        try? tokenStore.delete()
    }

    private static func send(_ request: URLRequest, using session: URLSession) async throws(ABSError) -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ABSError.notAudiobookshelf }
            return (data, http)
        } catch let error as ABSError {
            throw error
        } catch {
            throw .network(error.localizedDescription)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(ABSError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decoding
        }
    }
}

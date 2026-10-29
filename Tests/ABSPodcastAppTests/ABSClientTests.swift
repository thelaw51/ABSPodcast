@testable import ABSPodcastApp
import Foundation
import Synchronization
import Testing

/// Exercises the client against `StubServer`, using the response shapes of ABS v2.37.1.
struct ABSClientTests {
    let server: ServerURL

    init() throws {
        server = try ServerURL(parsing: "https://abs.example.com/abs")
    }

    @Test func statusAcceptsAudiobookshelf() async throws {
        let stub = StubServer.stub { _ in .ok(Fixture.status) }
        let status = try await ABSClient.status(of: server, session: stub.session)
        #expect(status.serverVersion == "2.37.1")
        #expect(status.authMethods == ["local"])
        #expect(stub.requests.first?.url?.path() == "/abs/status")
    }

    @Test func statusRejectsOtherSites() async {
        let stub = StubServer.stub { _ in .ok("<html>Not ABS</html>") }
        await #expect(throws: ABSError.notAudiobookshelf) {
            try await ABSClient.status(of: server, session: stub.session)
        }
    }

    @Test func loginAsksForTokensAndStoresThem() async throws {
        let store = InMemoryTokenStore()
        let stub = StubServer.stub { _ in .ok(Fixture.login(access: "a1", refresh: "r1")) }
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)

        let user = try await client.login(username: "joe", password: "secret")

        #expect(user.username == "joe")
        #expect(try store.load() == AuthTokens(accessToken: "a1", refreshToken: "r1"))
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/abs/login")
        #expect(request.value(forHTTPHeaderField: "x-return-tokens") == "true")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["username": "joe", "password": "secret"])
    }

    @Test func loginMapsWrongPassword() async {
        let stub = StubServer.stub { _ in .status(401) }
        let client = ABSClient(server: server, session: stub.session, tokenStore: InMemoryTokenStore())
        await #expect(throws: ABSError.invalidCredentials) {
            try await client.login(username: "joe", password: "wrong")
        }
    }

    @Test func loginRequiresRefreshToken() async throws {
        let store = InMemoryTokenStore()
        let stub = StubServer.stub { _ in .ok(Fixture.login(access: "a1", refresh: nil)) }
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)
        await #expect(throws: ABSError.missingRefreshToken) {
            try await client.login(username: "joe", password: "secret")
        }
        #expect(try store.load() == nil)
    }

    @Test func podcastLibrariesFiltersAndSorts() async throws {
        let stub = StubServer.stub { _ in .ok(Fixture.libraries) }
        let store = InMemoryTokenStore(AuthTokens(accessToken: "a1", refreshToken: "r1"))
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)

        let libraries = try await client.podcastLibraries()

        #expect(libraries.map(\.id) == ["lib_pod", "lib_pod2"])
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
    }

    @Test func expiredAccessTokenRefreshesAndRetries() async throws {
        let store = InMemoryTokenStore(AuthTokens(accessToken: "old", refreshToken: "r1"))
        let stub = StubServer.stub { request in
            if request.url?.path() == "/abs/auth/refresh" {
                return request.value(forHTTPHeaderField: "x-refresh-token") == "r1"
                    ? .ok(Fixture.login(access: "new", refresh: "r2"))
                    : .status(401)
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
                ? .ok(Fixture.libraries)
                : .status(401)
        }
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)

        let libraries = try await client.podcastLibraries()

        #expect(libraries.count == 2)
        #expect(try store.load() == AuthTokens(accessToken: "new", refreshToken: "r2"))
    }

    @Test func concurrentExpiredRequestsShareOneRefresh() async throws {
        let refreshCount = Mutex(0)
        let store = InMemoryTokenStore(AuthTokens(accessToken: "old", refreshToken: "r1"))
        let stub = StubServer.stub { request in
            if request.url?.path() == "/abs/auth/refresh" {
                refreshCount.withLock { $0 += 1 }
                // A second refresh with the rotated-away token would fail, as on a real server.
                return request.value(forHTTPHeaderField: "x-refresh-token") == "r1"
                    ? .ok(Fixture.login(access: "new", refresh: "r2"))
                    : .status(401)
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
                ? .ok(Fixture.libraries)
                : .status(401)
        }
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)

        async let first = client.podcastLibraries()
        async let second = client.podcastLibraries()
        async let third = client.podcastLibraries()
        let results = try await [first, second, third]

        #expect(results.allSatisfy { $0.count == 2 })
        #expect(refreshCount.withLock { $0 } == 1)
    }

    @Test func rejectedRefreshTokenEndsSession() async throws {
        let store = InMemoryTokenStore(AuthTokens(accessToken: "old", refreshToken: "revoked"))
        let stub = StubServer.stub { _ in .status(401) }
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)

        await #expect(throws: ABSError.sessionExpired) {
            try await client.podcastLibraries()
        }
        #expect(try store.load() == nil)
    }

    @Test func logoutRevokesAndClearsTokens() async throws {
        let store = InMemoryTokenStore(AuthTokens(accessToken: "a1", refreshToken: "r1"))
        let stub = StubServer.stub { _ in .ok("{}") }
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)

        await client.logout()

        let request = try #require(stub.requests.first)
        #expect(request.url?.path() == "/abs/logout")
        #expect(request.value(forHTTPHeaderField: "x-refresh-token") == "r1")
        #expect(try store.load() == nil)
    }

    @Test func refreshedTokensSurviveKeychainFailure() async throws {
        let store = FailingSaveTokenStore(AuthTokens(accessToken: "old", refreshToken: "r1"))
        let stub = StubServer.stub { request in
            if request.url?.path() == "/abs/auth/refresh" {
                return request.value(forHTTPHeaderField: "x-refresh-token") == "r1"
                    ? .ok(Fixture.login(access: "new", refresh: "r2"))
                    : .status(401)
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
                ? .ok(Fixture.libraries)
                : .status(401)
        }
        let client = ABSClient(server: server, session: stub.session, tokenStore: store)

        _ = try await client.podcastLibraries()
        // A second call must use the in-memory "new" token, not refresh again with "r1".
        _ = try await client.podcastLibraries()

        let refreshes = stub.requests.filter { $0.url?.path() == "/abs/auth/refresh" }
        #expect(refreshes.count == 1)
    }
}

/// Loads its initial tokens but fails every save, like a Keychain that refuses writes.
private final class FailingSaveTokenStore: TokenStore {
    private let initial: AuthTokens?
    init(_ initial: AuthTokens?) { self.initial = initial }
    func load() throws -> AuthTokens? { initial }
    func save(_ tokens: AuthTokens) throws { throw KeychainError(status: errSecInteractionNotAllowed) }
    func delete() throws {}
}

@testable import ABSPodcastApp
import Foundation
import Testing

@MainActor
struct SessionStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "SessionStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func signInStoresAccountAndRestoresOnRelaunch() async throws {
        let store = InMemoryTokenStore()
        let defaults = makeDefaults()
        let stub = StubServer.stub { request in
            request.url?.path() == "/status" ? .ok(Fixture.status) : .ok(Fixture.login(access: "a1", refresh: "r1"))
        }

        let sessionStore = SessionStore(tokenStore: store, defaults: defaults, urlSession: stub.session)
        try await sessionStore.signIn(serverAddress: "abs.example.com", username: " joe ", password: "secret")

        guard case .signedIn(let account) = sessionStore.state else {
            Issue.record("Expected signed in")
            return
        }
        #expect(account.username == "joe")
        #expect(account.server.base.absoluteString == "https://abs.example.com")

        let relaunched = SessionStore(tokenStore: store, defaults: defaults, urlSession: stub.session)
        #expect(relaunched.state == .signedIn(account))
    }

    @Test func signInStopsWhenPasswordLoginIsOff() async {
        let stub = StubServer.stub { _ in
            .ok(#"{"app":"audiobookshelf","serverVersion":"2.37.1","isInit":true,"authMethods":["openid"]}"#)
        }
        let sessionStore = SessionStore(tokenStore: InMemoryTokenStore(), defaults: makeDefaults(), urlSession: stub.session)

        await #expect(throws: ABSError.passwordLoginDisabled) {
            try await sessionStore.signIn(serverAddress: "abs.example.com", username: "joe", password: "secret")
        }
        #expect(stub.requests.count == 1)
    }

    @Test func expiredSessionSignsOut() async throws {
        let store = InMemoryTokenStore()
        let stub = StubServer.stub { request in
            request.url?.path() == "/status" ? .ok(Fixture.status) : .ok(Fixture.login(access: "a1", refresh: "r1"))
        }
        let sessionStore = SessionStore(tokenStore: store, defaults: makeDefaults(), urlSession: stub.session)
        try await sessionStore.signIn(serverAddress: "abs.example.com", username: "joe", password: "secret")

        sessionStore.handle(.sessionExpired)

        #expect(sessionStore.state == .signedOut)
        #expect(sessionStore.client == nil)
        #expect(try store.load() == nil)
    }

    @Test func missingTokensMeanSignedOutOnLaunch() async throws {
        let defaults = makeDefaults()
        let account = Account(server: try ServerURL(parsing: "abs.example.com"), userId: "usr_1", username: "joe")
        defaults.set(try JSONEncoder().encode(account), forKey: "signedInAccount")

        let sessionStore = SessionStore(tokenStore: InMemoryTokenStore(), defaults: defaults)

        #expect(sessionStore.state == .signedOut)
    }

    @Test func orphanedTokensAreDeletedOnLaunch() throws {
        let store = InMemoryTokenStore(AuthTokens(accessToken: "a1", refreshToken: "r1"))

        let sessionStore = SessionStore(tokenStore: store, defaults: makeDefaults())

        #expect(sessionStore.state == .signedOut)
        #expect(try store.load() == nil)
    }
}

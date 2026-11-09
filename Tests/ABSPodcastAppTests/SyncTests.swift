@testable import ABSPodcastApp
import Foundation
import Synchronization
import Testing

struct ListeningClockTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func countsOnlyTimeSpentPlaying() {
        var clock = ListeningClock()
        clock.tick(at: start, playing: true)
        clock.tick(at: start + 0.5, playing: true)
        clock.tick(at: start + 1, playing: true)
        // A stretch that ends stalled isn't counted; the stall could have begun any time in it.
        clock.tick(at: start + 1.5, playing: false)
        clock.tick(at: start + 10, playing: false)
        #expect(clock.unsent == 1)
    }

    @Test func capsLongGapsBetweenTicks() {
        var clock = ListeningClock()
        clock.tick(at: start, playing: true)
        clock.tick(at: start + 60, playing: true)
        #expect(clock.unsent == ListeningClock.maxTickGap)
    }

    @Test func stopKeepsAPauseOutOfTheCount() {
        var clock = ListeningClock()
        clock.tick(at: start, playing: true)
        clock.tick(at: start + 1, playing: true)
        clock.stop()
        clock.tick(at: start + 1.5, playing: true)
        #expect(clock.unsent == 1)
    }

    @Test func markSentKeepsTheFraction() {
        var clock = ListeningClock()
        clock.tick(at: start, playing: true)
        clock.tick(at: start + 1.5, playing: true)
        #expect(clock.wholeSeconds == 1)
        clock.markSent(1)
        #expect(clock.unsent == 0.5)
    }
}

struct PendingProgressStoreTests {
    private func account(_ userId: String) throws -> Account {
        Account(server: try ServerURL(parsing: "https://abs.example.com"), userId: userId, username: userId)
    }

    private func entry(_ episodeId: String, at time: Double) -> PendingProgress {
        PendingProgress(
            libraryItemId: "li_1", episodeId: episodeId, currentTime: time, duration: 100,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000.5)
        )
    }

    @Test func keepsTheLatestPositionPerEpisode() throws {
        let store = PendingProgressStore(account: try account("usr_1"), defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        store.save(entry("ep_1", at: 10))
        store.save(entry("ep_1", at: 20))
        store.save(entry("ep_2", at: 5))
        #expect(store.all.count == 2)
        #expect(store.entry(for: "ep_1")?.currentTime == 20)
    }

    @Test func accountsDoNotShareAQueue() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        PendingProgressStore(account: try account("usr_1"), defaults: defaults).save(entry("ep_1", at: 10))
        #expect(PendingProgressStore(account: try account("usr_2"), defaults: defaults).all.isEmpty)
    }

    @Test func removingAnOldEntryLeavesANewerOne() throws {
        let store = PendingProgressStore(account: try account("usr_1"), defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let older = entry("ep_1", at: 10)
        store.save(older)
        store.save(entry("ep_1", at: 20))
        store.remove(older)
        #expect(store.entry(for: "ep_1")?.currentTime == 20)
    }

    @Test func updateCarriesWhenItWasHeard() {
        #expect(entry("ep_1", at: 10).update.lastUpdate == 1_700_000_000_500)
    }
}

struct PlaybackSessionClientTests {
    let server: ServerURL

    init() throws {
        server = try ServerURL(parsing: "https://abs.example.com/abs")
    }

    private func client(_ stub: StubServer.Stub) -> ABSClient {
        ABSClient(server: server, session: stub.session, tokenStore: InMemoryTokenStore(AuthTokens(accessToken: "a1", refreshToken: "r1")))
    }

    @Test func startsADirectPlaySessionForThisDevice() async throws {
        let stub = StubServer.stub { _ in .ok(Fixture.playbackSession) }
        let device = DeviceInfo(deviceId: "dev_1", clientName: "Test", clientVersion: "1", manufacturer: "Apple", model: "iPhone")

        let opened = try await client(stub).startEpisodeSession(libraryItemId: "li_1", episodeId: "ep_new", device: device)

        #expect(opened.id == "sess_1")
        #expect(opened.currentTime == 1234)
        #expect(opened.audioTracks.first?.contentUrl == "/api/items/li_1/file/111")
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/abs/api/items/li_1/play/ep_new")
        let body = try jsonObject(request)
        #expect(body["forceDirectPlay"] as? Bool == true)
        #expect((body["deviceInfo"] as? [String: Any])?["deviceId"] as? String == "dev_1")
    }

    @Test func missingProgressIsNil() async throws {
        let stub = StubServer.stub { _ in .status(404) }
        #expect(try await client(stub).progress(libraryItemId: "li_1", episodeId: "ep_new") == nil)
    }

    @Test func progressWriteIsAPatch() async throws {
        let stub = StubServer.stub { _ in .ok("OK") }
        let update = ProgressUpdate(currentTime: 42, duration: nil, lastUpdate: 7)
        try await client(stub).updateProgress(libraryItemId: "li_1", episodeId: "ep_new", update)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path() == "/abs/api/me/progress/li_1/ep_new")
        let body = try jsonObject(request)
        #expect(body["currentTime"] as? Double == 42)
        #expect(body["lastUpdate"] as? Int == 7)
        #expect(body["duration"] == nil)
    }
}

@MainActor
struct PlaybackCoordinatorTests {
    let account: Account
    let defaults: UserDefaults
    let episode: Episode
    let podcast: PodcastMetadata

    init() throws {
        account = Account(server: try ServerURL(parsing: "https://abs.example.com/abs"), userId: "usr_1", username: "joe")
        defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(try JSONEncoder().encode(account), forKey: "signedInAccount")
        let detail = try JSONDecoder().decode(PodcastDetail.self, from: Data(Fixture.podcastDetail.utf8))
        episode = try #require(detail.media.episodes.first { $0.id == "ep_new" })
        podcast = detail.media.metadata
    }

    /// A coordinator signed in to a stubbed server, with a fake player.
    struct Harness {
        let coordinator: PlaybackCoordinator
        let player: FakePlayer
        let session: SessionStore
        let stub: StubServer.Stub
    }

    private func make(_ handle: @escaping StubServer.Handler) -> Harness {
        let stub = StubServer.stub(handling: handle)
        let session = SessionStore(
            tokenStore: InMemoryTokenStore(AuthTokens(accessToken: "a1", refreshToken: "r1")),
            defaults: defaults,
            urlSession: stub.session
        )
        let player = FakePlayer()
        return Harness(
            coordinator: PlaybackCoordinator(player: player, session: session, defaults: defaults),
            player: player, session: session, stub: stub
        )
    }

    private func start(_ harness: Harness) async throws {
        harness.coordinator.play(episode, podcast: podcast, libraryItemId: "li_1", artworkURL: nil, savedPosition: 99)
        try #require(await waitUntil { !harness.player.played.isEmpty })
    }

    private var queue: PendingProgressStore { PendingProgressStore(account: account, defaults: defaults) }

    @Test func resumesFromTheSessionAndStreamsItsTrack() async throws {
        let harness = make { _ in .ok(Fixture.playbackSession) }
        try await start(harness)

        let item = try #require(harness.player.played.first)
        #expect(item.startTime == 1234)
        #expect(item.streamURL.absoluteString == "https://abs.example.com/abs/api/items/li_1/file/111")
    }

    @Test func withoutASessionItPlaysTheFileFromTheSavedPosition() async throws {
        let harness = make { _ in .status(500) }
        try await start(harness)

        let item = try #require(harness.player.played.first)
        #expect(item.startTime == 99)
        #expect(item.streamURL.absoluteString == "https://abs.example.com/abs/api/items/li_1/file/98765")
    }

    @Test func signingOutWhileTheSessionOpensDropsIt() async throws {
        let gate = DispatchSemaphore(value: 0)
        let harness = make { request in
            if request.url?.path().contains("/play/") == true { gate.wait() }
            return .ok(Fixture.playbackSession)
        }
        harness.coordinator.play(episode, podcast: podcast, libraryItemId: "li_1", artworkURL: nil, savedPosition: 0)
        try #require(await waitUntil { !harness.stub.requests.isEmpty })

        await harness.coordinator.finishForSignOut()
        gate.signal()
        try await Task.sleep(for: .milliseconds(300))

        #expect(harness.player.played.isEmpty)
        #expect(harness.coordinator.startingEpisodeId == nil)
    }

    @Test func pauseSyncsThePositionAndClearsTheQueue() async throws {
        let harness = make { _ in .ok(Fixture.playbackSession) }
        try await start(harness)

        harness.player.listen(until: 600)
        harness.player.onEvent?(.paused)
        try #require(await waitUntil { harness.stub.requests.count == 2 })

        let sync = try #require(harness.stub.requests.last)
        #expect(sync.url?.path() == "/abs/api/session/sess_1/sync")
        #expect(try jsonObject(sync)["currentTime"] as? Double == 600)
        #expect(await waitUntil { queue.all.isEmpty })
    }

    @Test func aFailedSyncStaysQueued() async throws {
        let harness = make { request in
            request.url?.path().contains("/sync") == true ? .status(500) : .ok(Fixture.playbackSession)
        }
        try await start(harness)

        harness.player.listen(until: 600)
        harness.player.onEvent?(.paused)
        try #require(await waitUntil { harness.stub.requests.count == 2 })
        try await Task.sleep(for: .milliseconds(100))

        #expect(queue.entry(for: "ep_new")?.currentTime == 600)
    }

    @Test func aForgottenSessionFallsBackToWritingProgress() async throws {
        let harness = make { request in
            if request.url?.path().contains("/sync") == true { return .status(404) }
            if request.httpMethod == "GET" { return .status(404) }
            if request.httpMethod == "PATCH" { return .ok("OK") }
            return .ok(Fixture.playbackSession)
        }
        try await start(harness)

        harness.player.listen(until: 600)
        harness.player.onEvent?(.paused)
        try #require(await waitUntil { harness.stub.requests.count == 4 })

        let patch = try #require(harness.stub.requests.last)
        #expect(patch.httpMethod == "PATCH")
        #expect(try jsonObject(patch)["currentTime"] as? Double == 600)
        #expect(await waitUntil { queue.all.isEmpty })
    }

    @Test func aForgottenSessionNeverOverwritesNewerListening() async throws {
        let harness = make { request in
            if request.url?.path().contains("/sync") == true { return .status(404) }
            if request.httpMethod == "GET" { return .ok(Fixture.progressFromTheFuture) }
            return .ok(Fixture.playbackSession)
        }
        try await start(harness)

        harness.player.listen(until: 600)
        harness.player.onEvent?(.paused)
        try #require(await waitUntil { harness.stub.requests.count == 3 })
        try await Task.sleep(for: .milliseconds(100))

        #expect(!harness.stub.requests.contains { $0.httpMethod == "PATCH" })
        #expect(queue.all.isEmpty)
    }

    @Test func closingAfterNothingNewSendsNoPosition() async throws {
        let harness = make { _ in .ok(Fixture.playbackSession) }
        try await start(harness)
        harness.player.listen(until: 600)
        harness.player.onEvent?(.paused)
        try #require(await waitUntil { harness.stub.requests.count == 2 && queue.all.isEmpty })

        // Listening may have continued on another device since; this phone has nothing newer.
        await harness.coordinator.finishForSignOut()

        let close = try #require(harness.stub.requests.last)
        #expect(close.url?.path() == "/abs/api/session/sess_1/close")
        #expect(close.httpBody?.isEmpty ?? true)
        #expect(queue.all.isEmpty)
    }

    @Test func expiryQueuesOnlyAPositionTheServerLacks() async throws {
        let harness = make { _ in .ok(Fixture.playbackSession) }
        try await start(harness)
        harness.coordinator.reset()
        #expect(queue.all.isEmpty)
    }

    @Test func flushDropsAPositionOlderThanTheServers() async throws {
        let harness = make { _ in .ok(Fixture.progressFromTheFuture) }
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        queue.save(PendingProgress(libraryItemId: "li_1", episodeId: "ep_new", currentTime: 10, duration: nil, recordedAt: old))

        await harness.coordinator.flushPending()

        #expect(harness.stub.requests.map(\.httpMethod) == ["GET"])
        #expect(queue.all.isEmpty)
    }

    @Test func flushSendsAPositionNewerThanTheServers() async throws {
        let harness = make { request in
            request.httpMethod == "GET" ? .status(404) : .ok("OK")
        }
        queue.save(PendingProgress(libraryItemId: "li_1", episodeId: "ep_new", currentTime: 10, duration: nil, recordedAt: .now))

        await harness.coordinator.flushPending()

        #expect(harness.stub.requests.map(\.httpMethod) == ["GET", "PATCH"])
        #expect(queue.all.isEmpty)
    }

    @Test func signOutClosesTheSessionBeforeRevokingTokens() async throws {
        let harness = make { request in
            request.httpMethod == "GET" ? .status(404) : .ok(Fixture.playbackSession)
        }
        harness.session.beforeSignOut = { await harness.coordinator.finishForSignOut() }
        try await start(harness)
        harness.player.listen(until: 300)

        await harness.session.signOut()

        // No listening time to add, so the position is written through the check, then the
        // session closes empty, all before the refresh token is revoked.
        let calls = harness.stub.requests.compactMap { request in request.url.map { "\(request.httpMethod ?? "") \($0.path())" } }
        #expect(calls.suffix(4) == [
            "GET /abs/api/me/progress/li_1/ep_new",
            "PATCH /abs/api/me/progress/li_1/ep_new",
            "POST /abs/api/session/sess_1/close",
            "POST /abs/logout"
        ])
        #expect(harness.player.stopCount >= 1)
    }
}

/// Records what the coordinator asks of the player.
@MainActor
final class FakePlayer: PlaybackDriver {
    var currentTime: TimeInterval = 0
    var onEvent: (@MainActor (PlayerEvent) -> Void)?
    private(set) var played: [PlaybackItem] = []
    private(set) var stopCount = 0

    func play(_ item: PlaybackItem, tokens: TokenProvider) {
        played.append(item)
        currentTime = item.startTime
    }

    func pause() {}

    /// Moves the position forward with a playing tick, as a real player would.
    func listen(until time: TimeInterval) {
        currentTime = time
        onEvent?(.tick(playing: true))
    }

    func stop() {
        stopCount += 1
    }
}

/// Polls until `condition` holds, for work the code under test starts in its own Task.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

private func jsonObject(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

@testable import ABSPodcastApp
import Foundation
import MediaPlayer
import Testing

struct JWTTests {
    @Test func readsExpiry() {
        let token = makeJWT(exp: 1_800_000_000)
        #expect(JWT.expiry(of: token) == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test(arguments: ["", "x", ",", "ab"])
    func handlesEveryBase64PaddingLength(extra: String) {
        // Payload lengths that need 0, 1 and 2 padding characters.
        let token = makeJWT(exp: 1_800_000_000, extra: #","p":"\#(extra)""#)
        #expect(JWT.expiry(of: token) != nil)
    }

    @Test(arguments: ["", "not-a-jwt", "a.b", "a.!!!.c"])
    func rejectsMalformedTokens(token: String) {
        #expect(JWT.expiry(of: token) == nil)
    }
}

struct FreshAccessTokenTests {
    let server: ServerURL

    init() throws {
        server = try ServerURL(parsing: "https://abs.example.com/abs")
    }

    private func client(access: String, stub: StubServer.Stub) -> ABSClient {
        let store = InMemoryTokenStore(AuthTokens(accessToken: access, refreshToken: "r1"))
        return ABSClient(server: server, session: stub.session, tokenStore: store)
    }

    @Test func keepsTokenWithTimeToSpare() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let access = makeJWT(exp: now.timeIntervalSince1970 + 3000)
        let stub = StubServer.stub { _ in .status(500) }

        let token = try await client(access: access, stub: stub).freshAccessToken(minimumValidity: 600, now: now)

        #expect(token == access)
        #expect(stub.requests.isEmpty)
    }

    @Test func refreshesTokenCloseToExpiry() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let access = makeJWT(exp: now.timeIntervalSince1970 + 120)
        let stub = StubServer.stub { _ in .ok(Fixture.login(access: "new", refresh: "r2")) }

        let token = try await client(access: access, stub: stub).freshAccessToken(minimumValidity: 600, now: now)

        #expect(token == "new")
        #expect(stub.requests.first?.url?.path() == "/abs/auth/refresh")
    }

    @Test func forcedRefreshAlwaysAsksServer() async throws {
        let stub = StubServer.stub { _ in .ok(Fixture.login(access: "new", refresh: "r2")) }
        let token = try await client(access: makeJWT(exp: 9_999_999_999), stub: stub).refreshAccessToken()
        #expect(token == "new")
    }

    @Test func streamURLCannotLeaveTheServer() {
        let stub = StubServer.stub { _ in .status(500) }
        let url = client(access: "a", stub: stub).streamURL(contentPath: "https://evil.example.net/x")
        #expect(url.host() == "abs.example.com")
    }

    @Test func streamURLKeepsSubPath() {
        let stub = StubServer.stub { _ in .status(500) }
        let url = client(access: "a", stub: stub).streamURL(contentPath: "/api/items/li_1/file/98765")
        #expect(url.absoluteString == "https://abs.example.com/abs/api/items/li_1/file/98765")
    }
}

struct PlaybackItemTests {
    private func data() throws -> (PodcastDetail, EpisodeProgressIndex) {
        let detail = try JSONDecoder().decode(PodcastDetail.self, from: Data(Fixture.podcastDetail.utf8))
        let records = try JSONDecoder().decode(MediaProgressResponse.self, from: Data(Fixture.progress.utf8)).mediaProgress
        return (detail, EpisodeProgressIndex(records, libraryItemId: "li_1"))
    }

    @Test func buildsItemFromEpisodeWithAudio() throws {
        let (detail, progress) = try data()
        let episode = try #require(detail.media.episodes.first { $0.id == "ep_new" })
        let base = try #require(URL(string: "https://abs.example.com"))

        let item = try #require(PlaybackItem(
            episode: episode,
            podcast: detail.media.metadata,
            libraryItemId: detail.id,
            startTime: progress.resumePosition(for: episode),
            streamURL: { base.appending(path: String($0.dropFirst())) },
            artworkURL: nil
        ))

        #expect(item.streamURL.absoluteString == "https://abs.example.com/api/items/li_1/file/98765")
        #expect(item.startTime == 2700)
        #expect(item.duration == 5400)
        #expect(item.podcastTitle == "Accidental Tech")
    }

    @Test func episodeWithoutAudioIsNotPlayable() throws {
        let (detail, _) = try data()
        let episode = try #require(detail.media.episodes.first { $0.id == "ep_undated" })
        let item = PlaybackItem(
            episode: episode, podcast: detail.media.metadata, libraryItemId: detail.id,
            startTime: 0, streamURL: { _ in URL(fileURLWithPath: "/") }, artworkURL: nil
        )
        #expect(item == nil)
    }

    @Test func finishedEpisodesRestartFromTheBeginning() throws {
        let (detail, progress) = try data()
        let finished = try #require(detail.media.episodes.first { $0.id == "ep_old" })
        #expect(progress.resumePosition(for: finished) == 0)
    }
}

struct NowPlayingTests {
    private let item = PlaybackItem(
        episodeId: "e", libraryItemId: "li", title: "Episode", podcastTitle: "Show", author: "Host",
        artworkURL: nil, streamURL: URL(fileURLWithPath: "/a.mp3"), duration: 3600, startTime: 0
    )

    @Test func playingReportsChosenRate() {
        let info = NowPlaying.info(for: item, elapsed: 90, duration: 3600, rate: 1.5, isPlaying: true)
        #expect(info[MPMediaItemPropertyTitle] as? String == "Episode")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Show")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Host")
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 90)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5)
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 3600)
    }

    @Test func pausedReportsZeroRateSoTheClockStops() {
        let info = NowPlaying.info(for: item, elapsed: 90, duration: nil, rate: 1.5, isPlaying: false)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
        #expect(info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double == 1.5)
        #expect(info[MPMediaItemPropertyPlaybackDuration] == nil)
    }
}

struct PlayerMathTests {
    @Test func clampKeepsSeeksInsideTheEpisode() {
        #expect(AudioPlayer.clamp(-20, duration: 100) == 0)
        #expect(AudioPlayer.clamp(50, duration: 100) == 50)
        #expect(AudioPlayer.clamp(500, duration: 100) == 99)
        #expect(AudioPlayer.clamp(500, duration: nil) == 500)
    }

    @Test func clockFormatting() {
        #expect(Format.clock(0) == "0:00")
        #expect(Format.clock(65) == "1:05")
        #expect(Format.clock(3723) == "1:02:03")
        #expect(Format.clock(.nan) == "0:00")
    }

    @Test func rateLabels() {
        #expect(FullPlayerView.rateLabel(1) == "1×")
        #expect(FullPlayerView.rateLabel(1.5) == "1.5×")
        #expect(FullPlayerView.rateLabel(1.75) == "1.75×")
    }
}

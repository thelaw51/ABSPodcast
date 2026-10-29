import Foundation

/// Everything the player needs to play one episode, independent of how it was browsed to.
struct PlaybackItem: Equatable, Sendable {
    let episodeId: String
    let libraryItemId: String
    let title: String
    let podcastTitle: String
    let author: String?
    let artworkURL: URL?
    let streamURL: URL
    /// The length ABS reports. Preferred over AVPlayer's estimate, which drifts on VBR MP3s.
    let duration: TimeInterval?
    let startTime: TimeInterval
}

extension PlaybackItem {
    /// Builds an item for an episode, or nil if ABS has no audio file for it.
    ///
    /// An open ABS session's track and duration win over the episode's, since the server
    /// chose them for this playback.
    init?(
        episode: Episode,
        podcast: PodcastMetadata,
        libraryItemId: String,
        startTime: TimeInterval,
        streamURL: (String) -> URL,
        artworkURL: URL?,
        session: PlaybackSessionInfo? = nil
    ) {
        guard let contentPath = session?.audioTracks.first?.contentUrl ?? episode.audioTrack?.contentUrl else { return nil }
        self.init(
            episodeId: episode.id,
            libraryItemId: libraryItemId,
            title: episode.title,
            podcastTitle: podcast.title,
            author: podcast.author,
            artworkURL: artworkURL,
            streamURL: streamURL(contentPath),
            duration: session?.duration ?? episode.duration,
            startTime: startTime
        )
    }
}

/// How the player gets bearer tokens for audio requests, without holding the client itself.
struct TokenProvider: Sendable {
    /// A token with time to spare, refreshing first if the current one is close to expiry.
    let fresh: @Sendable () async throws -> String
    /// A new token, for when the server rejected the current one.
    let forceRefresh: @Sendable () async throws -> String

    init(client: ABSClient) {
        fresh = { try await client.freshAccessToken() }
        forceRefresh = { try await client.refreshAccessToken() }
    }
}

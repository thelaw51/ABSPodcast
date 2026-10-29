import Foundation

// Podcast payloads from ABS v2.37.1. Only `id` and `title` are required: real feeds leave
// almost everything else null, and one bad episode must not fail the whole list.

/// Podcast metadata shared by the list and detail payloads (`media.metadata`).
struct PodcastMetadata: Decodable, Hashable, Sendable {
    let title: String
    let author: String?
    /// HTML from the RSS feed. Use `PlainText.from(html:)` before showing it.
    let description: String?
    let explicit: Bool?
}

/// One podcast in a library listing (`GET /api/libraries/:id/items`, minified).
struct PodcastSummary: Decodable, Identifiable, Hashable, Sendable {
    struct Media: Decodable, Hashable, Sendable {
        let metadata: PodcastMetadata
        let numEpisodes: Int?
    }

    let id: String
    /// Milliseconds since 1970. Changes when the cover or metadata changes.
    let updatedAt: Int64?
    let media: Media
    /// Present only when requested, and omitted by ABS when it is zero.
    let numEpisodesIncomplete: Int?

    var title: String { media.metadata.title }
    var unplayedCount: Int { numEpisodesIncomplete ?? 0 }
}

/// Response from `GET /api/libraries/:id/items`.
struct LibraryItemsPage: Decodable, Sendable {
    let results: [PodcastSummary]
    let total: Int?
}

/// A podcast with its episodes (`GET /api/items/:id?expanded=1`).
struct PodcastDetail: Decodable, Identifiable, Sendable {
    struct Media: Decodable, Sendable {
        let metadata: PodcastMetadata
        let episodes: [Episode]
    }

    let id: String
    let updatedAt: Int64?
    let media: Media

    var title: String { media.metadata.title }

    /// Newest first. Episodes without a publish date fall back to when ABS added them.
    var episodesNewestFirst: [Episode] {
        media.episodes.sorted { $0.sortDate > $1.sortDate }
    }
}

/// One podcast episode.
struct Episode: Decodable, Identifiable, Hashable, Sendable {
    /// The episode's audio file. Only the expanded item payload includes it.
    struct AudioTrack: Decodable, Hashable, Sendable {
        /// Server-rooted path such as `/api/items/{id}/file/{ino}`. Needs the bearer token.
        let contentUrl: String
        let mimeType: String?
    }

    let id: String
    let libraryItemId: String?
    let title: String
    let subtitle: String?
    let description: String?
    let season: String?
    let episode: String?
    /// Milliseconds since 1970.
    let publishedAt: Int64?
    let addedAt: Int64?
    /// Seconds. Missing for episodes whose audio ABS hasn't probed.
    let duration: Double?
    let audioTrack: AudioTrack?

    var publishedDate: Date? { publishedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    fileprivate var sortDate: Int64 { publishedAt ?? addedAt ?? 0 }
}

/// The user's listening position for one book or episode (`GET /api/me/progress`).
struct MediaProgress: Decodable, Sendable {
    let libraryItemId: String?
    let episodeId: String?
    /// Seconds. ABS sometimes stores 0 when it didn't know the length.
    let duration: Double?
    /// 0...1.
    let progress: Double?
    let currentTime: Double?
    let isFinished: Bool
}

/// Response from `GET /api/me/progress`.
struct MediaProgressResponse: Decodable, Sendable {
    let mediaProgress: [MediaProgress]
}

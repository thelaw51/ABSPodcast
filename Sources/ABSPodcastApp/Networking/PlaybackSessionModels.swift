import Foundation

/// The device a playback session runs on, as ABS records it.
///
/// ABS closes a device's open session when the same `deviceId` starts another one, so the
/// ID must stay the same across launches.
struct DeviceInfo: Encodable, Equatable, Sendable {
    let deviceId: String
    let clientName: String
    let clientVersion: String
    let manufacturer: String
    let model: String
}

/// Body for `POST /api/items/:id/play/:episodeId`.
struct StartPlaybackRequest: Encodable, Sendable {
    let deviceInfo: DeviceInfo
    /// AVPlayer handles every format ABS stores podcasts in, so never ask for a transcode.
    var forceDirectPlay = true
    var mediaPlayer = "AVPlayer"
}

/// The parts of an ABS playback session the app uses.
struct PlaybackSessionInfo: Decodable, Sendable {
    let id: String
    /// Where to resume: the user's saved position, or 0 if the episode was finished.
    let currentTime: Double
    let duration: Double?
    let audioTracks: [Episode.AudioTrack]
}

/// Body for `POST /api/session/:id/sync` and `/close`.
struct SessionSync: Encodable, Equatable, Sendable {
    let currentTime: Double
    /// Whole seconds of real listening since the last accepted sync. ABS adds it to the
    /// session's total, so it must never be sent twice.
    let timeListened: Int
    let duration: Double?
}

/// Body for `PATCH /api/me/progress/:libraryItemId/:episodeId`.
struct ProgressUpdate: Encodable, Equatable, Sendable {
    let currentTime: Double
    let duration: Double?
    /// Milliseconds since 1970. ABS stores it as the record's `updatedAt`, so other clients
    /// see when the listening happened rather than when it reached the server.
    let lastUpdate: Int64
}

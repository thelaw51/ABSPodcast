import Foundation

/// How far the user is through one episode, as the episode list shows it.
enum EpisodeProgress: Equatable, Sendable {
    case unplayed
    /// `fraction` is 0...1. `remaining` is in seconds, or nil when the length is unknown.
    case inProgress(fraction: Double, remaining: TimeInterval?)
    case finished

    /// Derives the state from the server's progress record, if there is one.
    ///
    /// ABS sometimes records a duration of 0, so the episode's own duration is the fallback
    /// for working out time remaining.
    init(_ progress: MediaProgress?, episodeDuration: Double?) {
        guard let progress else {
            self = .unplayed
            return
        }
        if progress.isFinished {
            self = .finished
            return
        }

        let duration = [progress.duration, episodeDuration].compactMap { $0 }.first { $0 > 0 }
        let currentTime = progress.currentTime ?? 0
        let fraction = progress.progress.flatMap { $0 > 0 ? $0 : nil }
            ?? duration.map { currentTime / $0 }
            ?? 0

        guard fraction > 0 || currentTime > 0 else {
            self = .unplayed
            return
        }
        let remaining = duration.map { max(0, $0 - currentTime) }
        self = .inProgress(fraction: min(max(fraction, 0), 1), remaining: remaining)
    }
}

/// Indexes progress records by episode so a list can look each one up in constant time.
struct EpisodeProgressIndex: Sendable {
    private let byEpisode: [String: MediaProgress]

    init(_ records: [MediaProgress], libraryItemId: String) {
        var index: [String: MediaProgress] = [:]
        for record in records where record.libraryItemId == libraryItemId {
            if let episodeId = record.episodeId { index[episodeId] = record }
        }
        byEpisode = index
    }

    func progress(for episode: Episode) -> EpisodeProgress {
        EpisodeProgress(byEpisode[episode.id], episodeDuration: episode.duration)
    }
}

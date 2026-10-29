import Foundation

/// Something that happened in the player that progress sync cares about.
enum PlayerEvent: Equatable, Sendable {
    /// The periodic time update. `playing` is false while paused or buffering.
    case tick(playing: Bool)
    /// Playback stopped short of the end: the user paused, an interruption began, the
    /// output went away, or the stream failed.
    case paused
    case seeked
    case ended
}

/// What `PlaybackCoordinator` needs from a player. `AudioPlayer` is the real one; tests use
/// a fake so sync can be checked without AVFoundation.
@MainActor
protocol PlaybackDriver: AnyObject {
    var currentTime: TimeInterval { get }
    var onEvent: (@MainActor (PlayerEvent) -> Void)? { get set }
    func play(_ item: PlaybackItem, tokens: TokenProvider)
    func pause()
    func stop()
}

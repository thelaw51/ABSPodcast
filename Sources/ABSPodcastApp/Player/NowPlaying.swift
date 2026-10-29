import MediaPlayer
import UIKit

/// Builds lock screen and Control Center metadata.
///
/// iOS extrapolates elapsed time from the rate, so this only needs rebuilding on play, pause,
/// seek and rate changes, not on every clock tick.
enum NowPlaying {
    static func info(
        for item: PlaybackItem,
        elapsed: TimeInterval,
        duration: TimeInterval?,
        rate: Float,
        isPlaying: Bool
    ) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyAlbumTitle: item.podcastTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            // 0 tells iOS the clock is stopped; the chosen speed when playing.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate)
        ]
        if let author = item.author {
            info[MPMediaItemPropertyArtist] = author
        }
        if let duration, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        return info
    }

    /// Wraps an image for the lock screen.
    ///
    /// `nonisolated` on purpose: MediaPlayer calls the request handler on its own queue, and a
    /// closure created in main-actor code would trap Swift 6's isolation check there.
    nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

import Foundation

/// Counts wall-clock seconds of actual playback, the way ABS's own web player does.
///
/// Counting time rather than the change in position means 2× speed doesn't double the
/// listening stats and a skip forward isn't counted as listening.
struct ListeningClock {
    /// The player ticks twice a second. A longer gap means a stall or suspension, which
    /// isn't listening, so it is capped.
    static let maxTickGap: TimeInterval = 2

    /// Seconds listened that the server hasn't accepted yet.
    private(set) var unsent: TimeInterval = 0
    private var lastTick: Date?

    mutating func tick(at now: Date, playing: Bool) {
        defer { lastTick = playing ? now : nil }
        guard playing, let lastTick else { return }
        unsent += min(max(0, now.timeIntervalSince(lastTick)), Self.maxTickGap)
    }

    /// Ends the current stretch, so the time spent paused before the next tick isn't counted.
    mutating func stop() {
        lastTick = nil
    }

    /// The whole seconds to report. The fraction carries over to the next sync.
    var wholeSeconds: Int { Int(unsent) }

    /// Removes seconds the server accepted. Anything counted while the request was in
    /// flight stays for the next sync.
    mutating func markSent(_ seconds: Int) {
        unsent = max(0, unsent - TimeInterval(seconds))
    }
}

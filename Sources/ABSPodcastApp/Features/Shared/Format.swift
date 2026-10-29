import Foundation

/// Display formatting for durations and dates, so every screen words them the same way.
enum Format {
    /// "1 hr, 30 min", or "45 min".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 60)).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
    }

    /// "45 min left".
    static func remaining(_ seconds: TimeInterval) -> String {
        "\(duration(seconds)) left"
    }

    /// Player clock: "12:03", or "1:02:03" once it passes an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

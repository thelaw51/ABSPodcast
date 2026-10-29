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

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

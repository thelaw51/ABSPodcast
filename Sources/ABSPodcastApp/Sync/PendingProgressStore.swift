import Foundation

/// A position the server may not have yet.
struct PendingProgress: Codable, Equatable, Sendable {
    var id = UUID()
    let libraryItemId: String
    let episodeId: String
    let currentTime: Double
    let duration: Double?
    /// When this position was heard. Compared with the server's `lastUpdate` so a queued
    /// position never overwrites newer listening from another device.
    let recordedAt: Date

    var update: ProgressUpdate {
        ProgressUpdate(
            currentTime: currentTime,
            duration: duration,
            lastUpdate: Int64((recordedAt.timeIntervalSince1970 * 1000).rounded())
        )
    }
}

/// The latest unconfirmed position for each episode, kept in `UserDefaults` so it survives
/// a dead connection, an app kill and sign-out.
///
/// Positions are written before every sync and removed once the server accepts them.
/// Entries are kept per server and user, so one account's queue never reaches another's.
struct PendingProgressStore {
    private let defaults: UserDefaults
    private let key: String

    init(account: Account, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "pendingProgress|\(account.server.base.absoluteString)|\(account.userId)"
    }

    var all: [PendingProgress] { Array(load().values) }

    func entry(for episodeId: String) -> PendingProgress? {
        load()[episodeId]
    }

    /// Replaces any earlier position for the same episode.
    func save(_ entry: PendingProgress) {
        var entries = load()
        entries[entry.episodeId] = entry
        store(entries)
    }

    /// Removes `entry`, but not a newer position saved for the same episode since.
    func remove(_ entry: PendingProgress) {
        var entries = load()
        guard entries[entry.episodeId]?.id == entry.id else { return }
        entries[entry.episodeId] = nil
        store(entries)
    }

    private func load() -> [String: PendingProgress] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([String: PendingProgress].self, from: data) else { return [:] }
        return entries
    }

    private func store(_ entries: [String: PendingProgress]) {
        if entries.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}

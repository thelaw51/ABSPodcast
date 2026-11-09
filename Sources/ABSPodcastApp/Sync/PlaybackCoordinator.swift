import Foundation
import Observation

/// Starts episodes through ABS playback sessions and keeps the server's position current.
///
/// Views start episodes here rather than on the player. For each episode the coordinator:
/// 1. Sends any queued position for it, so the server's resume point is up to date.
/// 2. Opens an ABS session, which says where to resume and which file to stream.
/// 3. Reports the position and listening time every 15 seconds of listening, on pause,
///    once a seek settles, and at the end, where ABS marks the episode finished.
/// 4. Closes the session when another episode starts or the user signs out.
///
/// Each position is saved to `PendingProgressStore` before it is sent and removed once the
/// server accepts it, so nothing is lost to a dead connection or a killed app. ABS keeps open
/// sessions in memory, so after a server restart a sync gets a 404 and the coordinator
/// writes progress directly instead.
@MainActor
@Observable
final class PlaybackCoordinator {
    static let syncInterval: TimeInterval = 15
    static let seekSettleDelay: Duration = .seconds(2)
    /// How long sign-out waits for the final sync before revoking the tokens anyway.
    static let signOutTimeLimit: Duration = .seconds(4)

    /// Bumped when the server's progress changes, so screens showing it can refetch.
    private(set) var progressRevision = 0
    /// The episode whose session is opening, so its row can show that the tap registered.
    private(set) var startingEpisodeId: String?

    /// The episode being reported, and the client and account it belongs to.
    private struct Listening: Sendable {
        let id = UUID()
        let libraryItemId: String
        let episodeId: String
        let duration: Double?
        let client: ABSClient
        let account: Account
        var sessionId: String?
    }

    /// One position to report.
    private struct Report: Sendable {
        let listening: Listening
        let position: Double
        let listened: Int
        /// When audio last played or the user last seeked. A paused position is as old as
        /// this, however late it is sent, so newer listening elsewhere beats it.
        let heardAt: Date
        /// The change count this report covers.
        let changes: Int
        /// False if the server already has this position, in which case sending it again
        /// could undo newer listening on another device.
        let isNew: Bool

        var pending: PendingProgress {
            PendingProgress(
                libraryItemId: listening.libraryItemId,
                episodeId: listening.episodeId,
                currentTime: position,
                duration: listening.duration,
                recordedAt: heardAt
            )
        }
    }

    @ObservationIgnored private let player: any PlaybackDriver
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let device: DeviceInfo
    /// Bumped by every start and stop, so a session that opens late is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var current: Listening?
    @ObservationIgnored private var clock = ListeningClock()
    @ObservationIgnored private var nextPeriodicSync = Date.distantPast
    @ObservationIgnored private var lastHeard = Date.now
    /// Counts plays and seeks; a report is new if the server hasn't accepted this count yet.
    @ObservationIgnored private var changes = 0
    @ObservationIgnored private var acceptedChanges = 0
    /// Listening seconds carried by the sync in flight, so a close doesn't send them again.
    @ObservationIgnored private var inFlightSeconds = 0
    /// The episode whose sync is in flight, if any.
    @ObservationIgnored private var syncInFlight: UUID?
    @ObservationIgnored private var resyncRequested = false
    @ObservationIgnored private var seekSync: Task<Void, Never>?
    @ObservationIgnored private var isFlushing = false

    init(player: any PlaybackDriver, session: SessionStore, defaults: UserDefaults = .standard) {
        self.player = player
        self.session = session
        self.defaults = defaults
        device = DeviceIdentity.info(defaults: defaults)
        player.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - Commands

    /// Starts an episode, replacing whatever was playing. The previous episode's session is
    /// closed with its final position alongside, so a slow server doesn't delay the new one.
    ///
    /// `savedPosition` is used only if no session can be opened, in which case the episode
    /// plays straight from its file and progress is written directly.
    func play(_ episode: Episode, podcast: PodcastMetadata, libraryItemId: String, artworkURL: URL?, savedPosition: TimeInterval) {
        guard let client = session.client, case .signedIn(let account) = session.state else { return }
        generation += 1
        let startGeneration = generation
        let previous = detachCurrent()
        player.pause()
        startingEpisodeId = episode.id
        // If ABS opens the new session first it closes this one itself, and the late close
        // gets a 404 and writes the position directly instead.
        if let previous { Task { await send(previous, closing: true) } }

        Task {
            defer { if startGeneration == generation { startingEpisodeId = nil } }

            // ABS resumes a new session from its own copy, so bring that up to date first.
            let store = PendingProgressStore(account: account, defaults: defaults)
            if let queued = store.entry(for: episode.id) { await flush(queued, client: client, store: store) }
            guard startGeneration == generation else { return }

            var opened: PlaybackSessionInfo?
            do throws(ABSError) {
                opened = try await client.startEpisodeSession(libraryItemId: libraryItemId, episodeId: episode.id, device: device)
            } catch {
                if error == .sessionExpired, session.client === client { session.handle(error) }
            }
            guard startGeneration == generation, session.client === client else { return }

            // A position that still couldn't be sent is newer than anything the server has.
            let start = store.entry(for: episode.id)?.currentTime ?? opened?.currentTime ?? savedPosition
            guard let item = PlaybackItem(
                episode: episode,
                podcast: podcast,
                libraryItemId: libraryItemId,
                startTime: start,
                streamURL: client.streamURL(contentPath:),
                artworkURL: artworkURL,
                session: opened
            ) else { return }

            current = Listening(
                libraryItemId: libraryItemId,
                episodeId: episode.id,
                duration: item.duration,
                client: client,
                account: account,
                sessionId: opened?.id
            )
            nextPeriodicSync = .now + Self.syncInterval
            player.play(item, tokens: TokenProvider(client: client))
        }
    }

    /// Sends the final position and closes the session, before sign-out revokes the tokens.
    ///
    /// Gives up after a few seconds so an offline sign-out isn't held up. Whatever didn't get
    /// through stays queued for this account's next sign-in.
    func finishForSignOut() async {
        guard let report = stopAll() else { return }
        await withTimeLimit(Self.signOutTimeLimit) { _ = await self.send(report, closing: true) }
    }

    /// Stops playback without contacting the server, for when the session has already ended.
    /// The position stays queued for the next sign-in to the same account.
    func reset() {
        guard let report = stopAll(), report.isNew else { return }
        PendingProgressStore(account: report.listening.account, defaults: defaults).save(report.pending)
    }

    /// Sends positions queued by syncs that didn't get through, oldest listening first.
    /// Call on launch and whenever the app comes back to the foreground.
    func flushPending() async {
        guard !isFlushing, let client = session.client, case .signedIn(let account) = session.state else { return }
        isFlushing = true
        defer { isFlushing = false }
        let store = PendingProgressStore(account: account, defaults: defaults)
        // The current episode's own syncs supersede its queued position.
        for entry in store.all.sorted(by: { $0.recordedAt < $1.recordedAt }) where entry.episodeId != current?.episodeId {
            await flush(entry, client: client, store: store)
        }
    }

    // MARK: - Reporting

    private func handle(_ event: PlayerEvent) {
        guard current != nil else { return }
        switch event {
        case .tick(let playing):
            clock.tick(at: .now, playing: playing)
            if playing { noteChange() }
            if clock.unsent >= Self.syncInterval, Date.now >= nextPeriodicSync { syncNow(announce: false) }
        case .paused, .ended:
            clock.stop()
            syncNow(announce: true)
        case .seeked:
            noteChange()
            // A run of skips sends one sync once they stop.
            seekSync?.cancel()
            seekSync = Task {
                try? await Task.sleep(for: Self.seekSettleDelay)
                guard !Task.isCancelled else { return }
                syncNow(announce: false)
            }
        }
    }

    /// Reports the current position. A request already in flight finishes first, then this
    /// one runs with the position at that point.
    private func syncNow(announce: Bool) {
        guard let listening = current else { return }
        guard syncInFlight == nil else {
            resyncRequested = true
            return
        }
        let report = makeReport(for: listening)
        guard report.isNew || report.listened > 0 else { return }
        syncInFlight = listening.id
        inFlightSeconds = report.listened
        // After a failure, wait a full interval rather than retrying on every tick.
        nextPeriodicSync = .now + Self.syncInterval

        Task {
            let accepted = await send(report, closing: false, announce: announce)
            if accepted, current?.id == listening.id {
                clock.markSent(report.listened)
                acceptedChanges = max(acceptedChanges, report.changes)
            }
            if current?.id == listening.id { inFlightSeconds = 0 }
            // A late sync for the previous episode mustn't release the current one's slot.
            guard syncInFlight == listening.id else { return }
            syncInFlight = nil
            if resyncRequested {
                resyncRequested = false
                syncNow(announce: true)
            }
        }
    }

    /// Saves the position, then reports it. Returns true once the server has it.
    @discardableResult
    private func send(_ report: Report, closing: Bool, announce: Bool = true) async -> Bool {
        let listening = report.listening
        guard report.isNew || report.listened > 0 else {
            // Nothing the server doesn't have. Close without a position, so one that went
            // stale while paused can't overwrite listening on another device.
            if closing, let sessionId = listening.sessionId {
                try? await listening.client.closeSession(id: sessionId, nil)
            }
            return true
        }

        let store = PendingProgressStore(account: listening.account, defaults: defaults)
        let pending = report.pending
        store.save(pending)

        // A pause in the background suspends the app within seconds of the audio stopping.
        let backgroundTime = BackgroundTime("Progress sync")
        defer { backgroundTime.end() }

        do throws(ABSError) {
            try await deliver(report, as: pending, closing: closing)
        } catch {
            if error == .sessionExpired, session.client === listening.client { session.handle(error) }
            return false
        }

        store.remove(pending)
        if announce { progressRevision += 1 }
        return true
    }

    /// Sends one queued position, unless the server already has newer listening for it.
    private func flush(_ entry: PendingProgress, client: ABSClient, store: PendingProgressStore) async {
        do throws(ABSError) {
            if try await writeIfNewer(entry, with: client) { progressRevision += 1 }
            store.remove(entry)
        } catch .http(status: 404) {
            // The episode is gone from the server.
            store.remove(entry)
        } catch {
            // Kept for the next attempt.
            if error == .sessionExpired, session.client === client { session.handle(error) }
        }
    }

    // MARK: - Helpers

    private func noteChange() {
        changes += 1
        lastHeard = .now
    }

    private func makeReport(for listening: Listening) -> Report {
        Report(
            listening: listening,
            position: player.currentTime,
            listened: max(0, clock.wholeSeconds - inFlightSeconds),
            heardAt: lastHeard,
            changes: changes,
            isNew: changes != acceptedChanges
        )
    }

    /// Stops reporting the current episode and returns its final position.
    private func detachCurrent() -> Report? {
        guard let listening = current else { return nil }
        current = nil
        syncInFlight = nil
        resyncRequested = false
        seekSync?.cancel()
        clock.stop()
        let report = makeReport(for: listening)
        clock = ListeningClock()
        changes = 0
        acceptedChanges = 0
        inFlightSeconds = 0
        return report
    }

    private func stopAll() -> Report? {
        generation += 1
        startingEpisodeId = nil
        let report = detachCurrent()
        player.stop()
        return report
    }
}

// MARK: - Delivery

extension PlaybackCoordinator {
    /// Gets one report to the server: through the session when it adds listening time,
    /// otherwise as a direct write checked against the server's copy.
    private func deliver(_ report: Report, as pending: PendingProgress, closing: Bool) async throws(ABSError) {
        let listening = report.listening
        guard let sessionId = listening.sessionId else {
            _ = try await writeIfNewer(pending, with: listening.client)
            return
        }

        // A close with no listening to add carries only a position, which ABS would apply
        // unconditionally. Write it through the check instead, then close empty. The session
        // closes even if the write fails; the position stays queued.
        if closing, report.listened == 0 {
            var failure: ABSError?
            do throws(ABSError) {
                _ = try await writeIfNewer(pending, with: listening.client)
            } catch {
                failure = error
            }
            try? await listening.client.closeSession(id: sessionId, nil)
            if let failure { throw failure }
            return
        }

        let update = SessionSync(currentTime: report.position, timeListened: report.listened, duration: listening.duration)
        do throws(ABSError) {
            if closing {
                try await listening.client.closeSession(id: sessionId, update)
            } else {
                try await listening.client.syncSession(id: sessionId, update)
            }
        } catch .http(status: 404) {
            // ABS keeps open sessions in memory, so a server restart forgets them.
            if current?.id == listening.id { current?.sessionId = nil }
            _ = try await writeIfNewer(pending, with: listening.client)
        }
    }

    /// Writes a position directly, unless the server has newer listening for the episode.
    /// ABS applies a progress write unconditionally, so the check has to happen here.
    /// Returns whether it wrote.
    private func writeIfNewer(_ entry: PendingProgress, with client: ABSClient) async throws(ABSError) -> Bool {
        let serverCopy = try await client.progress(libraryItemId: entry.libraryItemId, episodeId: entry.episodeId)
        // Compares this phone's clock with the server's. Skew of a few seconds could drop a
        // position, which is acceptable next to overwriting newer listening.
        if let lastUpdate = serverCopy?.lastUpdate, lastUpdate > entry.update.lastUpdate { return false }
        try await client.updateProgress(libraryItemId: entry.libraryItemId, episodeId: entry.episodeId, entry.update)
        return true
    }
}

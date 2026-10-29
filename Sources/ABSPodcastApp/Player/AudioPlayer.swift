import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Plays one episode at a time, in the background, with lock screen controls.
///
/// Audio requests carry the ABS bearer token, and an access token lasts an hour. The player
/// asks for a token with at least ten minutes left when it loads or resumes, and if the
/// server still rejects a request mid-episode, it refreshes once and reloads at the last
/// position that played.
///
/// Phase 3 keeps the position in memory only. Phase 4 adds ABS playback sessions so the
/// position syncs to the server.
@MainActor
@Observable
final class AudioPlayer {
    static let skipBackInterval: TimeInterval = 15
    static let skipForwardInterval: TimeInterval = 30
    static let rates: [Float] = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0]

    private(set) var item: PlaybackItem?
    /// Whether the user wants audio playing. Stays true while buffering.
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var rate: Float = 1.0
    private(set) var errorMessage: String?

    /// ABS's duration when known, otherwise AVPlayer's estimate.
    var duration: TimeInterval? { item?.duration ?? assetDuration }
    private var assetDuration: TimeInterval?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var tokens: TokenProvider?
    @ObservationIgnored private var tokenExpiry: Date?
    /// Bumped on every load and stop, so late callbacks from an old item are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingSeek: TimeInterval?
    @ObservationIgnored private var lastGoodTime: TimeInterval = 0
    @ObservationIgnored private var recoveryAttempted = false
    @ObservationIgnored private var pausedByInterruption = false
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var itemStatusObserver: NSKeyValueObservation?
    @ObservationIgnored private var itemNotificationObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var playerObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private var audioSessionObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private let remoteCommands = RemoteCommands()

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        audioSessionObservers = AudioSessionEvents.observe(
            onInterruption: { [weak self] type, options in self?.handleInterruption(type, options: options) },
            onOutputLost: { [weak self] in self?.pause() }
        )
    }

    // MARK: - Commands

    /// Starts an episode from its `startTime`, replacing whatever was playing.
    ///
    /// Synchronous on purpose: callers on the main actor can't interleave it with `stop()`,
    /// so a tap just before sign-out can't bring a stale episode back afterwards.
    func play(_ newItem: PlaybackItem, tokens provider: TokenProvider) {
        generation += 1
        let loadGeneration = generation

        item = newItem
        tokens = provider
        errorMessage = nil
        assetDuration = nil
        artwork = nil
        currentTime = newItem.startTime
        lastGoodTime = newItem.startTime
        recoveryAttempted = false
        isPlaying = true
        isBuffering = true

        activateAudioSession()
        remoteCommands.install(for: self)
        updateNowPlaying()
        loadArtwork(for: newItem, generation: loadGeneration)
        pendingSeek = nil
        Task { await loadAsset(at: newItem.startTime, generation: loadGeneration, forceRefresh: false) }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        isPlaying = false
        player.pause()
        updateNowPlaying()
    }

    /// Resumes, reloading with a fresh token first if the current one is about to expire.
    /// A long pause followed by a lock screen resume is the usual way a token runs out.
    func resume() {
        guard item != nil else { return }
        isPlaying = true
        errorMessage = nil
        activateAudioSession()

        // A finished episode starts again rather than sitting at the end.
        if let duration, currentTime >= duration - 1 {
            currentTime = 0
            lastGoodTime = 0
            if player.currentItem?.status == .readyToPlay { player.seek(to: .zero) }
        }

        if tokenRunningOut || player.currentItem == nil || player.currentItem?.status == .failed {
            reload(at: currentTime, forceRefresh: false)
        } else {
            player.play()
        }
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        guard item != nil else { return }
        let target = Self.clamp(time, duration: duration)
        currentTime = target
        lastGoodTime = target
        if player.currentItem?.status == .readyToPlay {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            pendingSeek = target
        }
        updateNowPlaying()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        // play() resumes at defaultRate, so the speed survives pause and lock screen toggles.
        player.defaultRate = newRate
        if isPlaying { player.rate = newRate }
        updateNowPlaying()
    }

    /// Stops playback and forgets the episode, the token source and the lock screen entry.
    /// Called on sign-out, so nothing keeps streaming with a revoked session.
    func stop() {
        generation += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeItemObservers()
        item = nil
        tokens = nil
        tokenExpiry = nil
        assetDuration = nil
        pendingSeek = nil
        isPlaying = false
        isBuffering = false
        currentTime = 0
        errorMessage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        remoteCommands.remove()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Loading

    private func reload(at time: TimeInterval, forceRefresh: Bool) {
        generation += 1
        let loadGeneration = generation
        isBuffering = true
        Task { await loadAsset(at: time, generation: loadGeneration, forceRefresh: forceRefresh) }
    }

    private func loadAsset(at time: TimeInterval, generation loadGeneration: Int, forceRefresh: Bool) async {
        guard let item, let tokens else { return }

        let token: String
        do {
            token = forceRefresh ? try await tokens.forceRefresh() : try await tokens.fresh()
        } catch {
            guard loadGeneration == generation else { return }
            fail(error)
            return
        }
        guard loadGeneration == generation else { return }

        // AVPlayer has no public API for request headers. This option key is the long-standing
        // way to send one, and it keeps the token out of the URL, logs and cache keys.
        //
        // Accepted risk: AVPlayer uses its own networking, so ABSClient's same-origin redirect
        // policy doesn't cover media, and a cross-origin redirect could carry this header with
        // it. ABS serves files without redirecting, and the only other party in the path is
        // the Cloudflare tunnel, which already terminates TLS. Closing this fully would mean
        // proxying media through an AVAssetResourceLoaderDelegate.
        let asset = AVURLAsset(url: item.streamURL, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]
        ])
        let playerItem = AVPlayerItem(asset: asset)
        // Keeps voices natural at faster speeds.
        playerItem.audioTimePitchAlgorithm = .timeDomain

        tokenExpiry = JWT.expiry(of: token)
        pendingSeek = time > 0 ? time : nil
        observe(playerItem, generation: loadGeneration)
        player.replaceCurrentItem(with: playerItem)
        player.defaultRate = rate
    }

    private func handleItemReady(_ playerItem: AVPlayerItem) {
        let seconds = playerItem.duration.seconds
        if seconds.isFinite, seconds > 0 { assetDuration = seconds }

        guard let target = pendingSeek else {
            if isPlaying { player.play() }
            return
        }
        pendingSeek = nil
        let loadGeneration = generation
        Task {
            await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard loadGeneration == generation, isPlaying else { return }
            player.play()
            updateNowPlaying()
        }
    }

    /// One retry at the last position that played. The retry allowance comes back once
    /// playback moves forward again.
    ///
    /// AVPlayer doesn't say whether a failure was a 401, so the token's own expiry decides:
    /// only a token at or near expiry is force-refreshed. A network blip just reloads, which
    /// avoids rotating the 30-day refresh token on every dropped connection.
    private func handleItemFailure(_ error: (any Error)?) {
        guard item != nil else { return }
        guard !recoveryAttempted else {
            fail(error)
            return
        }
        recoveryAttempted = true
        reload(at: lastGoodTime, forceRefresh: tokenRunningOut)
    }

    /// Whether the token AVPlayer holds is within the safety margin of expiring. An unreadable
    /// expiry counts as fine; the server is the judge then.
    private var tokenRunningOut: Bool {
        tokenExpiry.map { $0.timeIntervalSinceNow < ABSClient.tokenSafetyMargin } ?? false
    }

    private func handlePlayedToEnd() {
        isPlaying = false
        if let duration { currentTime = duration }
        updateNowPlaying()
    }

    private func fail(_ error: (any Error)?) {
        player.pause()
        isPlaying = false
        isBuffering = false
        errorMessage = (error as? ABSError)?.localizedDescription
            ?? "Playback stopped. Check your connection and try again."
        updateNowPlaying()
    }

    private func handleTick(_ seconds: TimeInterval) {
        guard seconds.isFinite, pendingSeek == nil, player.currentItem != nil else { return }
        currentTime = seconds
        if seconds > lastGoodTime + 1 {
            lastGoodTime = seconds
            recoveryAttempted = false
        }
    }

    // MARK: - Observation
    //
    // Callbacks hop to the main actor themselves; see PlayerSystemHooks.swift for why.

    private func observePlayer() {
        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.handleTick(time.seconds) }
        }

        let observation = PlayerObservation.timeControl(of: player) { [weak self] status in
            Task { @MainActor in self?.isBuffering = status == .waitingToPlayAtSpecifiedRate }
        }
        playerObservers = [observation]
    }

    private func observe(_ playerItem: AVPlayerItem, generation loadGeneration: Int) {
        removeItemObservers()

        itemStatusObserver = PlayerObservation.status(of: playerItem) { [weak self, weak playerItem] status, error in
            Task { @MainActor in
                guard let self, let playerItem, loadGeneration == self.generation else { return }
                switch status {
                case .readyToPlay: self.handleItemReady(playerItem)
                case .failed: self.handleItemFailure(error)
                default: break
                }
            }
        }

        let center = NotificationCenter.default
        let failed = center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, loadGeneration == self.generation else { return }
                self.handleItemFailure(nil)
            }
        }
        let ended = center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, loadGeneration == self.generation else { return }
                self.handlePlayedToEnd()
            }
        }
        itemNotificationObservers = [failed, ended]
    }

    private func removeItemObservers() {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        itemNotificationObservers.forEach(NotificationCenter.default.removeObserver)
        itemNotificationObservers = []
    }
}

extension AudioPlayer {
    /// Clamps a seek target into the playable range.
    nonisolated static func clamp(_ time: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        let upper = duration.map { max(0, $0 - 1) } ?? .greatestFiniteMagnitude
        return min(max(0, time), upper)
    }
}

// MARK: - System integration

extension AudioPlayer {
    // MARK: - Audio session

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // Long-form spoken audio: ducks correctly and routes to AirPlay the way podcast apps do.
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            // The system has already paused the player; record it so the UI agrees.
            pausedByInterruption = isPlaying
            isPlaying = false
            updateNowPlaying()
        case .ended:
            if pausedByInterruption, options.contains(.shouldResume) { resume() }
            pausedByInterruption = false
        default:
            break
        }
    }

    // MARK: - Lock screen

    private func updateNowPlaying() {
        guard let item else { return }
        var info = NowPlaying.info(for: item, elapsed: currentTime, duration: duration, rate: rate, isPlaying: isPlaying)
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for item: PlaybackItem, generation loadGeneration: Int) {
        guard let url = item.artworkURL else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  loadGeneration == generation else { return }
            artwork = NowPlaying.artwork(image)
            updateNowPlaying()
        }
    }
}

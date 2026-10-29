import AVFoundation
import MediaPlayer

// AVFoundation and MediaPlayer call back on queues of their choosing. Every callback here is
// @Sendable and hops to the main actor itself. A closure written inside main-actor code would
// instead be main-actor isolated, and Swift 6 traps when the framework runs it elsewhere.

/// KVO helpers whose callbacks are not main-actor isolated.
enum PlayerObservation {
    nonisolated static func timeControl(
        of player: AVPlayer,
        _ handler: @escaping @Sendable (AVPlayer.TimeControlStatus) -> Void
    ) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.new]) { player, _ in handler(player.timeControlStatus) }
    }

    nonisolated static func status(
        of item: AVPlayerItem,
        _ handler: @escaping @Sendable (AVPlayerItem.Status, (any Error)?) -> Void
    ) -> NSKeyValueObservation {
        item.observe(\.status, options: [.new]) { item, _ in handler(item.status, item.error) }
    }
}

/// Audio session notifications the player reacts to.
enum AudioSessionEvents {
    /// Reports interruptions (calls, Siri, alarms), and output devices going away, such as
    /// headphones unplugged or Bluetooth dropping, where the player should pause rather than
    /// carry on through the speaker.
    @MainActor
    static func observe(
        onInterruption: @escaping @MainActor (AVAudioSession.InterruptionType?, AVAudioSession.InterruptionOptions) -> Void,
        onOutputLost: @escaping @MainActor () -> Void
    ) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        let interruption = center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
            MainActor.assumeIsolated { onInterruption(type, options) }
        }

        let routeChange = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { onOutputLost() }
        }

        return [interruption, routeChange]
    }
}

/// Lock screen, Control Center and headphone button handlers.
@MainActor
final class RemoteCommands {
    private var targets: [(MPRemoteCommand, Any)] = []

    func install(for player: AudioPlayer) {
        guard targets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: AudioPlayer.skipBackInterval)]
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: AudioPlayer.skipForwardInterval)]
        // With track commands enabled, iOS shows next/previous instead of the skip buttons.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false

        add(center.playCommand, for: player) { $0.resume() }
        add(center.pauseCommand, for: player) { $0.pause() }
        add(center.togglePlayPauseCommand, for: player) { $0.togglePlayPause() }
        add(center.skipBackwardCommand, for: player) { $0.skip(by: -AudioPlayer.skipBackInterval) }
        add(center.skipForwardCommand, for: player) { $0.skip(by: AudioPlayer.skipForwardInterval) }

        let positionCommand = center.changePlaybackPositionCommand
        let positionTarget = Self.addTarget(positionCommand) { [weak player] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in player?.seek(to: position) }
            return .success
        }
        positionCommand.isEnabled = true
        targets.append((positionCommand, positionTarget))
    }

    func remove() {
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        targets = []
    }

    private func add(_ command: MPRemoteCommand, for player: AudioPlayer, perform action: @escaping @MainActor (AudioPlayer) -> Void) {
        let target = Self.addTarget(command) { [weak player] _ in
            Task { @MainActor in
                guard let player else { return }
                action(player)
            }
            return .success
        }
        command.isEnabled = true
        targets.append((command, target))
    }

    nonisolated private static func addTarget(
        _ command: MPRemoteCommand,
        _ handler: @escaping @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) -> Any {
        command.addTarget(handler: handler)
    }
}

import SwiftUI

/// App entry point. Owns the session store, the single audio player and the coordinator that
/// syncs its progress, and hands them to every view through the environment.
@main
struct ABSPodcastApp: App {
    @State private var session: SessionStore
    @State private var player: AudioPlayer
    @State private var playback: PlaybackCoordinator

    init() {
        let session = SessionStore()
        let player = AudioPlayer()
        let playback = PlaybackCoordinator(player: player, session: session)
        session.beforeSignOut = { [weak playback] in await playback?.finishForSignOut() }
        _session = State(initialValue: session)
        _player = State(initialValue: player)
        _playback = State(initialValue: playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(player)
                .environment(playback)
        }
    }
}

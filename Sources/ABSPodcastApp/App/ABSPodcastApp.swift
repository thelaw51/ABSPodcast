import SwiftUI

/// App entry point. Owns the session store and the single audio player, and hands both to
/// every view through the environment.
@main
struct ABSPodcastApp: App {
    @State private var session = SessionStore()
    @State private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(player)
        }
    }
}

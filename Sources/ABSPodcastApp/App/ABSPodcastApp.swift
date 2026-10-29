import SwiftUI

/// App entry point. Owns the session store and hands it to every view through the environment.
@main
struct ABSPodcastApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}

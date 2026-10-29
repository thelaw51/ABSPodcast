import SwiftUI

/// App entry point. Owns the root scene and, in later phases, the shared
/// session and player state that the views read from the environment.
@main
struct ABSPodcastApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

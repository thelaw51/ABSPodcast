import SwiftUI

/// Top-level view. Shows sign-in until there is a session, then the libraries with the
/// mini player pinned above them.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlayerOpen = false

    var body: some View {
        Group {
            switch session.state {
            case .signedOut:
                SignInView()
            case .signedIn(let account):
                LibraryListView(account: account)
                    .id(account.server.base.absoluteString + account.userId)
                    .safeAreaInset(edge: .bottom) {
                        MiniPlayerView { isPlayerOpen = true }
                    }
                    .sheet(isPresented: $isPlayerOpen) {
                        FullPlayerView()
                    }
                    // Positions queued by syncs that failed, possibly in an earlier launch.
                    .task(id: account.userId) { await playback.flushPending() }
            }
        }
        .onChange(of: session.state) {
            // Any change of account, including sign-out and an expired session, ends playback,
            // so nothing keeps streaming with, or holding, the previous account's token.
            isPlayerOpen = false
            playback.reset()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await playback.flushPending() } }
        }
    }
}

#Preview {
    let session = SessionStore(tokenStore: PreviewTokenStore())
    let player = AudioPlayer()
    RootView()
        .environment(session)
        .environment(player)
        .environment(PlaybackCoordinator(player: player, session: session))
}

import SwiftUI

/// Top-level view. Shows sign-in until there is a session, then the libraries with the
/// mini player pinned above them.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AudioPlayer.self) private var player
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
            }
        }
        .onChange(of: session.state) {
            // Any change of account, including sign-out and an expired session, ends playback,
            // so nothing keeps streaming with, or holding, the previous account's token.
            isPlayerOpen = false
            player.stop()
        }
    }
}

#Preview {
    RootView()
        .environment(SessionStore(tokenStore: PreviewTokenStore()))
        .environment(AudioPlayer())
}

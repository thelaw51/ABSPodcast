import SwiftUI

/// Top-level view. Shows sign-in until there is a session, then the user's libraries.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.state {
        case .signedOut:
            SignInView()
        case .signedIn(let account):
            LibraryListView(account: account)
                .id(account.server.base.absoluteString + account.userId)
        }
    }
}

#Preview {
    RootView()
        .environment(SessionStore(tokenStore: PreviewTokenStore()))
}

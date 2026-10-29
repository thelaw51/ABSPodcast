import SwiftUI

/// The signed-in user's podcast libraries. Phase 2 makes each row open its podcasts.
struct LibraryListView: View {
    let account: Account
    @Environment(SessionStore.self) private var session

    private enum LoadState {
        case loading
        case loaded([Library])
        case failed(String)
    }

    @State private var loadState = LoadState.loading

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Libraries")
                .toolbar { accountMenu }
                .task { await load() }
                .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Libraries", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .loaded(let libraries) where libraries.isEmpty:
            ContentUnavailableView(
                "No Podcast Libraries",
                systemImage: "mic.slash",
                description: Text("This account can't see any podcast libraries on \(account.server.displayName).")
            )
        case .loaded(let libraries):
            List(libraries) { library in
                Label(library.name, systemImage: "mic")
            }
        }
    }

    private var accountMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("\(account.username) on \(account.server.displayName)") {
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            } label: {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        if case .failed = loadState { loadState = .loading }
        do {
            loadState = .loaded(try await client.podcastLibraries())
        } catch {
            session.handle(error)
            loadState = .failed(error.localizedDescription)
        }
    }
}

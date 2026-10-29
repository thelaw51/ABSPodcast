import SwiftUI

/// The signed-in user's podcast libraries, and the root of the browse navigation stack.
///
/// With a single podcast library, which is the usual setup, the app opens it straight away.
/// The back button still returns here, where the account menu lives.
struct LibraryListView: View {
    let account: Account
    @Environment(SessionStore.self) private var session

    @State private var loadState = LoadState<[Library]>.loading
    @State private var path = NavigationPath()
    @State private var didAutoOpen = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Libraries")
                .toolbar { accountMenu }
                .task { await load() }
                .refreshable { await load() }
                .navigationDestination(for: Library.self) { PodcastGridView(library: $0) }
                .navigationDestination(for: PodcastSummary.self) { EpisodeListView(podcast: $0) }
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
                NavigationLink(value: library) {
                    Label(library.name, systemImage: "mic")
                }
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
            let libraries = try await client.podcastLibraries()
            loadState = .loaded(libraries)
            if !didAutoOpen, libraries.count == 1, path.isEmpty {
                didAutoOpen = true
                path.append(libraries[0])
            }
        } catch {
            session.handle(error)
            loadState = .failed(error.localizedDescription)
        }
    }
}

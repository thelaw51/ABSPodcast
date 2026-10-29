import SwiftUI

/// Loads the podcasts in one library and shows them as a searchable grid.
struct PodcastGridView: View {
    let library: Library
    @Environment(SessionStore.self) private var session
    @State private var loadState = LoadState<[PodcastSummary]>.loading
    @State private var searchText = ""

    var body: some View {
        content
            .navigationTitle(library.name)
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Podcasts", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .loaded(let podcasts) where podcasts.isEmpty:
            ContentUnavailableView("No Podcasts", systemImage: "mic.slash", description: Text("\(library.name) is empty."))
        case .loaded(let podcasts):
            PodcastGrid(podcasts: filtered(podcasts), coverURL: coverURL)
                .searchable(text: $searchText, prompt: "Search \(library.name)")
                .overlay {
                    if !searchText.isEmpty && filtered(podcasts).isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
        }
    }

    private func filtered(_ podcasts: [PodcastSummary]) -> [PodcastSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return podcasts }
        return podcasts.filter {
            $0.title.localizedStandardContains(query) || ($0.media.metadata.author?.localizedStandardContains(query) ?? false)
        }
    }

    private func coverURL(_ podcast: PodcastSummary) -> URL? {
        session.client?.coverURL(itemId: podcast.id, updatedAt: podcast.updatedAt, width: 400)
    }

    private func load() async {
        guard let client = session.client else { return }
        if case .failed = loadState { loadState = .loading }
        do {
            loadState = .loaded(try await client.podcasts(inLibrary: library.id))
        } catch {
            session.handle(error)
            loadState = .failed(error.localizedDescription)
        }
    }
}

/// The grid itself, separate from loading so previews can render it from sample data.
struct PodcastGrid: View {
    let podcasts: [PodcastSummary]
    let coverURL: (PodcastSummary) -> URL?

    // Top alignment keeps covers level when one tile has no author line.
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(podcasts) { podcast in
                    NavigationLink(value: podcast) {
                        PodcastTile(podcast: podcast, coverURL: coverURL(podcast))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

/// Cover, title and author, with a badge counting unplayed episodes.
struct PodcastTile: View {
    let podcast: PodcastSummary
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: coverURL)
                .overlay(alignment: .topTrailing) {
                    if podcast.unplayedCount > 0 {
                        Text(podcast.unplayedCount, format: .number)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.tint, in: Capsule())
                            .padding(6)
                    }
                }
            Text(podcast.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let author = podcast.media.metadata.author {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(podcast.unplayedCount > 0 ? "\(podcast.unplayedCount) unplayed" : "")
    }
}

#if DEBUG
#Preview("Grid") {
    NavigationStack {
        PodcastGrid(podcasts: PreviewData.podcasts) { _ in nil }
            .navigationTitle("Podcasts")
    }
}
#endif

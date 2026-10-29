import SwiftUI

/// Loads one podcast's episodes and the user's progress, then lists the episodes newest first.
struct EpisodeListView: View {
    let podcast: PodcastSummary
    @Environment(SessionStore.self) private var session
    @State private var loadState = LoadState<EpisodeListData>.loading

    var body: some View {
        content
            .navigationTitle(podcast.title)
            .navigationBarTitleDisplayMode(.inline)
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
                Label("Couldn't Load Episodes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .loaded(let data):
            EpisodeList(data: data, coverURL: session.client?.coverURL(itemId: podcast.id, updatedAt: podcast.updatedAt, width: 300))
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        if case .failed = loadState { loadState = .loading }
        do {
            // Both requests are independent, so run them side by side.
            async let detail = client.podcast(id: podcast.id)
            async let progress = client.mediaProgress()
            let loadedDetail = try await detail
            let index = EpisodeProgressIndex(try await progress, libraryItemId: podcast.id)
            loadState = .loaded(EpisodeListData(detail: loadedDetail, progress: index))
        } catch let error as ABSError {
            session.handle(error)
            loadState = .failed(error.localizedDescription)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

/// What the episode list needs once loading finishes.
struct EpisodeListData {
    let detail: PodcastDetail
    let progress: EpisodeProgressIndex
}

/// The episode list itself, separate from loading so previews can render it from sample data.
struct EpisodeList: View {
    let data: EpisodeListData
    let coverURL: URL?

    var body: some View {
        List {
            Section {
                PodcastHeader(metadata: data.detail.media.metadata, coverURL: coverURL)
            }
            Section("\(data.detail.media.episodes.count) Episodes") {
                ForEach(data.detail.episodesNewestFirst) { episode in
                    EpisodeRow(episode: episode, progress: data.progress.progress(for: episode))
                }
            }
        }
        .overlay {
            if data.detail.media.episodes.isEmpty {
                ContentUnavailableView("No Episodes", systemImage: "mic.slash")
            }
        }
    }
}

/// Artwork, title, author and a collapsible plain-text description.
struct PodcastHeader: View {
    let metadata: PodcastMetadata
    let coverURL: URL?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CoverImage(url: coverURL)
                    .frame(width: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title)
                        .font(.headline)
                    if let author = metadata.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let description = metadata.description.map(PlainText.from(html:)), !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 3)
                    .onTapGesture { withAnimation { isExpanded.toggle() } }
                    .accessibilityHint(isExpanded ? "Collapses the description" : "Shows the full description")
            }
        }
        .padding(.vertical, 4)
    }
}

/// One episode: date, title, and either its length, time left, or a played mark.
struct EpisodeRow: View {
    let episode: Episode
    let progress: EpisodeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = episode.publishedDate {
                Text(Format.date(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(episode.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(progress == .finished ? .secondary : .primary)
                .lineLimit(2)
            status
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        switch progress {
        case .finished:
            // Not a Label: inside a List it reserves a wide icon column and indents the text.
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Played")
            }
        case .inProgress(let fraction, let remaining):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .frame(width: 60)
                    .accessibilityHidden(true)
                Text(remaining.map(Format.remaining) ?? "\(Int(fraction * 100))% played")
            }
        case .unplayed:
            if let duration = episode.duration {
                Text(Format.duration(duration))
            }
        }
    }
}

#if DEBUG
#Preview("Episodes") {
    NavigationStack {
        EpisodeList(data: PreviewData.episodeList, coverURL: nil)
            .navigationTitle("Accidental Tech")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

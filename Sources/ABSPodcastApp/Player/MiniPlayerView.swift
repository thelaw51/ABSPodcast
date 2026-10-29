import SwiftUI

/// Compact player pinned above the content while an episode is loaded. Tapping it opens the
/// full player.
struct MiniPlayerView: View {
    @Environment(AudioPlayer.self) private var player
    let onOpen: () -> Void

    var body: some View {
        if let item = player.item {
            HStack(spacing: 12) {
                CoverImage(url: item.artworkURL, cornerRadius: 6)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.podcastTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                PlayPauseButton(size: .title2)
                Button {
                    player.skip(by: AudioPlayer.skipForwardInterval)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.title3)
                }
                .accessibilityLabel("Skip forward 30 seconds")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottom) { progressLine }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAction(named: "Open player", onOpen)
        }
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            let fraction = player.duration.map { $0 > 0 ? player.currentTime / $0 : 0 } ?? 0
            Rectangle()
                .fill(.tint)
                .frame(width: proxy.size.width * min(max(fraction, 0), 1), height: 2)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// Play/pause, showing a spinner while the stream buffers.
struct PlayPauseButton: View {
    @Environment(AudioPlayer.self) private var player
    var size: Font = .title

    var body: some View {
        Button(action: player.togglePlayPause) {
            ZStack {
                if player.isPlaying && player.isBuffering {
                    ProgressView()
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .font(size)
            .frame(minWidth: 32, minHeight: 32)
        }
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }
}

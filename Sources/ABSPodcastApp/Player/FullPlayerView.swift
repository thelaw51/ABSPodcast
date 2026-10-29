import AVKit
import SwiftUI

/// Full-screen player: artwork, scrubber, transport controls, speed and output picker.
struct FullPlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var scrubTime: TimeInterval?

    var body: some View {
        if let item = player.item {
            VStack(spacing: 24) {
                Spacer(minLength: 8)
                CoverImage(url: item.artworkURL, cornerRadius: 16)
                    .frame(maxWidth: 320)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .scaleEffect(player.isPlaying ? 1 : 0.92)
                    .animation(.spring(duration: 0.4), value: player.isPlaying)

                VStack(spacing: 6) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(item.podcastTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                scrubber
                transport
                if let message = player.errorMessage {
                    errorBanner(message)
                }
                Spacer(minLength: 8)
                accessories
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .presentationDragIndicator(.visible)
        }
    }

    private var scrubber: some View {
        let duration = max(player.duration ?? 0, 1)
        let shown = scrubTime ?? player.currentTime
        return VStack(spacing: 4) {
            Slider(
                value: Binding(get: { shown }, set: { scrubTime = $0 }),
                in: 0...duration
            ) { editing in
                // Seek once on release, not on every drag step.
                if !editing, let target = scrubTime {
                    player.seek(to: target)
                    scrubTime = nil
                }
            }
            .accessibilityLabel("Position")
            .accessibilityValue("\(Format.clock(shown)) of \(Format.clock(duration))")
            HStack {
                Text(Format.clock(shown))
                Spacer()
                Text("-" + Format.clock(max(0, duration - shown)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private var transport: some View {
        HStack(spacing: 44) {
            Button {
                player.skip(by: -AudioPlayer.skipBackInterval)
            } label: {
                Image(systemName: "gobackward.15").font(.title)
            }
            .accessibilityLabel("Skip back 15 seconds")

            PlayPauseButton(size: .system(size: 48))

            Button {
                player.skip(by: AudioPlayer.skipForwardInterval)
            } label: {
                Image(systemName: "goforward.30").font(.title)
            }
            .accessibilityLabel("Skip forward 30 seconds")
        }
        .buttonStyle(.plain)
    }

    private var accessories: some View {
        HStack {
            Menu {
                Picker("Speed", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    ForEach(AudioPlayer.rates, id: \.self) { rate in
                        Text(Self.rateLabel(rate)).tag(rate)
                    }
                }
            } label: {
                Text(Self.rateLabel(player.rate))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            .accessibilityLabel("Playback speed")
            .accessibilityValue(Self.rateLabel(player.rate))
            Spacer()
            RoutePicker()
                .frame(width: 44, height: 44)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Try Again", action: player.resume)
                .buttonStyle(.bordered)
        }
    }

    /// "1×", "1.5×", "1.75×".
    static func rateLabel(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

/// AirPlay and Bluetooth output picker.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

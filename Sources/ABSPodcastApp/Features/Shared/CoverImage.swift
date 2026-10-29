import SwiftUI

/// Square podcast artwork with a placeholder while it loads or when there is none.
///
/// Uses `AsyncImage`, which goes through `URLSession.shared` and its on-disk cache. That is
/// fine because ABS serves covers without auth, so no token ends up in the cache.
struct CoverImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "mic")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

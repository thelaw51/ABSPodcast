import SwiftUI

/// Top-level view. Phase 1 replaces the placeholder with a switch between the
/// sign-in flow and the library, driven by whether a saved session exists.
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            AppInfo.displayName,
            systemImage: "headphones",
            description: Text("Version \(AppInfo.version). Server sign-in arrives in the next update.")
        )
    }
}

#Preview {
    RootView()
}

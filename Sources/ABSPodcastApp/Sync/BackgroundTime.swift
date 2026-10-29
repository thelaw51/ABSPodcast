import Foundation
import UIKit

/// Runs `operation`, but returns after `limit` even if it hasn't finished, cancelling it.
func withTimeLimit(_ limit: Duration, _ operation: @escaping @Sendable @MainActor () async -> Void) async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await operation() }
        group.addTask { try? await Task.sleep(for: limit) }
        await group.next()
        group.cancelAll()
    }
}

/// Asks iOS for a little more time to run, so a sync started just before suspension finishes.
@MainActor
final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

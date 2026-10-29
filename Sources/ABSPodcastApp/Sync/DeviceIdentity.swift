import Foundation
import UIKit

/// How this install identifies itself to ABS when it opens playback sessions.
enum DeviceIdentity {
    private static let idKey = "deviceId"

    /// The device record to send, creating and keeping a random ID on first use.
    ///
    /// The ID is random rather than `identifierForVendor`, so it reveals nothing beyond
    /// "the same install as before".
    @MainActor
    static func info(defaults: UserDefaults = .standard) -> DeviceInfo {
        let id: String
        if let saved = defaults.string(forKey: idKey) {
            id = saved
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: idKey)
        }
        return DeviceInfo(
            deviceId: id,
            clientName: AppInfo.displayName,
            clientVersion: AppInfo.version,
            manufacturer: "Apple",
            model: UIDevice.current.model
        )
    }
}

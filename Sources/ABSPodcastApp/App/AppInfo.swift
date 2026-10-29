import Foundation

/// Read-only facts about the running build, taken from the bundle's Info.plist.
enum AppInfo {
    static var displayName: String {
        string(for: "CFBundleDisplayName") ?? string(for: "CFBundleName") ?? "ABSPodcastApp"
    }

    /// Marketing version and build number, for example "0.1.0 (1)".
    static var version: String {
        let marketing = string(for: "CFBundleShortVersionString") ?? "0"
        let build = string(for: "CFBundleVersion") ?? "0"
        return "\(marketing) (\(build))"
    }

    private static func string(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

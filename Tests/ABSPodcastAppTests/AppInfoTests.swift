@testable import ABSPodcastApp
import Testing

/// Smoke tests that prove the test target links against the app and runs.
struct AppInfoTests {
    @Test func versionIncludesBuildNumber() {
        #expect(AppInfo.version.contains("("))
        #expect(AppInfo.version.hasSuffix(")"))
    }

    @Test func displayNameIsNotEmpty() {
        #expect(!AppInfo.displayName.isEmpty)
    }
}

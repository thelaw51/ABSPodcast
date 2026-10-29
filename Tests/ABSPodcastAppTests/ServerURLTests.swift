@testable import ABSPodcastApp
import Testing

struct ServerURLTests {
    @Test func addsHTTPSWhenSchemeIsMissing() throws {
        let server = try ServerURL(parsing: "abs.example.com")
        #expect(server.base.absoluteString == "https://abs.example.com")
    }

    @Test func trimsWhitespaceTrailingSlashesAndQuery() throws {
        let server = try ServerURL(parsing: "  https://ABS.example.com/abs//?x=1#top \n")
        #expect(server.base.absoluteString == "https://abs.example.com/abs")
    }

    @Test func resolvesEndpointsUnderSubPath() throws {
        let server = try ServerURL(parsing: "https://example.com/audiobookshelf/")
        #expect(server.url(for: "api/libraries").absoluteString == "https://example.com/audiobookshelf/api/libraries")
        #expect(server.url(for: "login").absoluteString == "https://example.com/audiobookshelf/login")
    }

    @Test func keepsCustomPort() throws {
        let server = try ServerURL(parsing: "abs.example.com:8443")
        #expect(server.url(for: "status").absoluteString == "https://abs.example.com:8443/status")
    }

    @Test(arguments: ["", "   ", "http://abs.example.com", "ftp://abs.example.com", "https://", "https://joe:secret@abs.example.com"])
    func rejectsUnusableAddresses(input: String) {
        #expect(throws: ABSError.self) { try ServerURL(parsing: input) }
    }
}

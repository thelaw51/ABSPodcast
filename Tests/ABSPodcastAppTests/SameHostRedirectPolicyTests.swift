@testable import ABSPodcastApp
import Foundation
import Testing

struct SameHostRedirectPolicyTests {
    private func redirect(from origin: String, to target: String) async throws -> URLRequest? {
        let originURL = try #require(URL(string: origin))
        let targetURL = try #require(URL(string: target))
        let task = URLSession(configuration: .ephemeral).dataTask(with: originURL)
        let response = try #require(HTTPURLResponse(url: originURL, statusCode: 307, httpVersion: nil, headerFields: nil))
        return await SameHostRedirectPolicy().urlSession(
            .shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: targetURL)
        )
    }

    @Test func followsRedirectOnSameHost() async throws {
        let result = try await redirect(from: "https://abs.example.com/login", to: "https://abs.example.com/abs/login")
        #expect(result != nil)
    }

    @Test(arguments: ["https://evil.example.net/login", "http://abs.example.com/login", "https://abs.example.com:8443/login"])
    func refusesRedirectOffOrigin(target: String) async throws {
        let result = try await redirect(from: "https://abs.example.com/login", to: target)
        #expect(result == nil)
    }
}

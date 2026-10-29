@testable import ABSPodcastApp
import Foundation
import Synchronization

/// A fake ABS server. Each stub gets its own `URLSession`, so tests can run in parallel.
///
/// The session tags every request with a stub ID header, which `startLoading` uses to find
/// the right handler.
final class StubServer: URLProtocol {
    struct Response {
        var status: Int
        var json: String

        static func ok(_ json: String) -> Response { Response(status: 200, json: json) }
        static func status(_ code: Int) -> Response { Response(status: code, json: "{}") }
    }

    typealias Handler = @Sendable (URLRequest) -> Response

    /// One stubbed server: the session to hand to the code under test, and what it received.
    struct Stub {
        let id: String
        let session: URLSession
        var requests: [URLRequest] { StubServer.recorded.withLock { $0[id] ?? [] } }
    }

    private static let idHeader = "X-Stub-ID"
    private static let handlers = Mutex<[String: Handler]>([:])
    private static let recorded = Mutex<[String: [URLRequest]]>([:])

    static func stub(handling handle: @escaping Handler) -> Stub {
        let id = UUID().uuidString
        handlers.withLock { $0[id] = handle }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        config.httpAdditionalHeaders = [idHeader: id]
        return Stub(id: id, session: URLSession(configuration: config))
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // URLSession moves httpBody into a stream before it reaches a protocol, so copy it back.
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Data(reading: stream)
        }

        guard let id = request.value(forHTTPHeaderField: Self.idHeader),
              let handle = Self.handlers.withLock({ $0[id] }),
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        Self.recorded.withLock { $0[id, default: []].append(request) }

        let reply = handle(request)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Token store backed by memory, so tests never touch the Keychain.
final class InMemoryTokenStore: TokenStore {
    private let tokens: Mutex<AuthTokens?>

    init(_ initial: AuthTokens? = nil) {
        tokens = Mutex(initial)
    }

    func load() throws -> AuthTokens? { tokens.withLock { $0 } }
    func save(_ newTokens: AuthTokens) throws { tokens.withLock { $0 = newTokens } }
    func delete() throws { tokens.withLock { $0 = nil } }
}

/// Canned ABS response bodies, trimmed to the fields the app decodes plus a few it ignores.
enum Fixture {
    static let status = """
    {"app":"audiobookshelf","serverVersion":"2.37.1","isInit":true,"language":"en-us","authMethods":["local"],"authFormData":{}}
    """

    static func login(access: String, refresh: String?) -> String {
        let refreshJSON = refresh.map { "\"\($0)\"" } ?? "null"
        return """
        {"user":{"id":"usr_1","username":"joe","type":"root","accessToken":"\(access)","refreshToken":\(refreshJSON)},
         "userDefaultLibraryId":"lib_pod","serverSettings":{},"ereaderDevices":[],"Source":"docker"}
        """
    }

    static let libraries = """
    {"libraries":[
      {"id":"lib_book","name":"Audiobooks","mediaType":"book","displayOrder":1,"icon":"audiobookshelf","folders":[]},
      {"id":"lib_pod2","name":"Archive","mediaType":"podcast","displayOrder":3,"icon":"podcast","folders":[]},
      {"id":"lib_pod","name":"Podcasts","mediaType":"podcast","displayOrder":2,"icon":"podcast","folders":[]}
    ]}
    """
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

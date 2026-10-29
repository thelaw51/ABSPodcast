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

/// Builds an unsigned JWT with the given `exp`, enough for code that only reads claims.
func makeJWT(exp: TimeInterval, extra: String = "") -> String {
    func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = base64URL(#"{"alg":"HS256","typ":"JWT"}"#)
    let payload = base64URL(#"{"userId":"usr_1","type":"access"\#(extra),"exp":\#(Int(exp))}"#)
    return "\(header).\(payload).signature"
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

    /// Two podcasts. The second has a null author and ABS left out numEpisodesIncomplete (zero).
    static let podcasts = """
    {"results":[
      {"id":"li_1","libraryId":"lib_pod","updatedAt":1761730000000,"mediaType":"podcast","numEpisodesIncomplete":3,
       "media":{"id":"pod_1","numEpisodes":10,"tags":[],"coverPath":"/x.jpg",
        "metadata":{"title":"Accidental Tech","author":"ATP","description":"<p>Three nerds</p>","explicit":false,"genres":[]}}},
      {"id":"li_2","libraryId":"lib_pod","updatedAt":null,"mediaType":"podcast",
       "media":{"id":"pod_2","numEpisodes":4,"tags":[],"coverPath":null,
        "metadata":{"title":"Backlog","author":null,"description":null,"explicit":null,"genres":[]}}}
    ],"total":2,"limit":0,"page":0,"mediaType":"podcast","minified":true}
    """

    /// One podcast with three episodes, one missing publishedAt, duration and season.
    static let podcastDetail = """
    {"id":"li_1","updatedAt":1761730000000,"mediaType":"podcast",
     "media":{"id":"pod_1","libraryItemId":"li_1","numEpisodes":3,"tags":[],
      "metadata":{"title":"Accidental Tech","author":"ATP","description":"<p>Three nerds</p>","explicit":false},
      "episodes":[
        {"id":"ep_old","libraryItemId":"li_1","title":"Old","season":"1","episode":"1","publishedAt":1700000000000,
         "addedAt":1700000000000,"duration":3600.5,"enclosure":null,"chapters":[]},
        {"id":"ep_new","libraryItemId":"li_1","title":"New","subtitle":"Latest","season":null,"episode":null,
         "publishedAt":1760000000000,"addedAt":1760000000000,"duration":5400,
         "enclosure":{"url":"https://x","type":"audio/mpeg","length":null},
         "audioTrack":{"index":1,"startOffset":0,"ino":"98765","contentUrl":"/api/items/li_1/file/98765","mimeType":"audio/mpeg"}},
        {"id":"ep_undated","libraryItemId":"li_1","title":"Undated","publishedAt":null,"addedAt":1750000000000}
      ]}}
    """

    static let progress = """
    {"mediaProgress":[
      {"id":"mp1","libraryItemId":"li_1","episodeId":"ep_new","mediaItemType":"podcastEpisode","duration":0,
       "progress":0.5,"currentTime":2700,"isFinished":false,"lastUpdate":1761000000000},
      {"id":"mp2","libraryItemId":"li_1","episodeId":"ep_old","mediaItemType":"podcastEpisode","duration":3600,
       "progress":1,"currentTime":3600,"isFinished":true,"lastUpdate":1761000000000},
      {"id":"mp3","libraryItemId":"li_other","episodeId":"ep_undated","mediaItemType":"podcastEpisode","duration":100,
       "progress":0.2,"currentTime":20,"isFinished":false,"lastUpdate":1761000000000},
      {"id":"mp4","libraryItemId":"li_book","episodeId":null,"mediaItemType":"book","duration":100,
       "progress":0.2,"currentTime":20,"isFinished":false,"lastUpdate":1761000000000}
    ]}
    """

    static let libraries = """
    {"libraries":[
      {"id":"lib_future","name":"Comics","mediaType":"comic","displayOrder":4,"icon":null,"folders":[]},
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

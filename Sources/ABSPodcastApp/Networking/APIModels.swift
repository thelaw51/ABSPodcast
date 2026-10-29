import Foundation

/// Response from the unauthenticated `GET /status` endpoint.
struct ServerStatus: Decodable, Sendable {
    let app: String?
    let serverVersion: String
    let isInit: Bool
    let authMethods: [String]
}

/// Response from `POST /login` and `POST /auth/refresh`. Only the fields the app uses are decoded.
struct LoginResponse: Decodable, Sendable {
    struct User: Decodable, Sendable {
        let id: String
        let username: String
        let accessToken: String
        /// Present only when the request sent `x-return-tokens` (login) or `x-refresh-token` (refresh).
        let refreshToken: String?
    }

    let user: User
}

/// What a library holds. Unknown values decode as `.other` so a future ABS type can't break the list.
enum MediaType: Hashable, Sendable, Decodable {
    case book
    case podcast
    case other(String)

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "book": self = .book
        case "podcast": self = .podcast
        default: self = .other(raw)
        }
    }
}

/// A library on the server. A library holds either books or podcasts, never both.
struct Library: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let mediaType: MediaType
    let displayOrder: Int
    let icon: String?

    var isPodcastLibrary: Bool { mediaType == .podcast }
}

/// Response from `GET /api/libraries`.
struct LibrariesResponse: Decodable, Sendable {
    let libraries: [Library]
}

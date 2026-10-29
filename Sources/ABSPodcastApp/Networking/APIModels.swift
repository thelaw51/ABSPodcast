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

/// A library on the server. A library holds either books or podcasts, never both.
struct Library: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let mediaType: String
    let displayOrder: Int
    let icon: String?

    var isPodcastLibrary: Bool { mediaType == "podcast" }
}

/// Response from `GET /api/libraries`.
struct LibrariesResponse: Decodable, Sendable {
    let libraries: [Library]
}

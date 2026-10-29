import Foundation

/// Follows a redirect only when it stays on the same scheme, host and port.
///
/// URLSession resends the body and custom headers on a 307/308 redirect, so following one
/// to another host would hand it the password (`/login`) or the refresh token.
final class SameHostRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let origin = task.originalRequest?.url, let target = request.url else { return nil }
        let sameOrigin = origin.scheme == target.scheme && origin.host() == target.host() && origin.port == target.port
        return sameOrigin ? request : nil
    }
}

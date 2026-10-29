import Foundation

/// Every failure the app reports from talking to an Audiobookshelf server.
enum ABSError: Error, Equatable, LocalizedError {
    case invalidServerURL(String)
    /// The address answered, but not with the ABS status payload.
    case notAudiobookshelf
    case passwordLoginDisabled
    case invalidCredentials
    case tooManyAttempts
    /// The server didn't return a refresh token, which ABS versions before JWT sessions don't.
    case missingRefreshToken
    /// The refresh token was rejected or is missing, so the user must sign in again.
    case sessionExpired
    /// Signing in worked but the Keychain refused to store the tokens.
    case tokenStorage
    case http(status: Int)
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidServerURL(let reason):
            reason
        case .notAudiobookshelf:
            "No Audiobookshelf server answered at that address. Check the URL, including any sub-path."
        case .passwordLoginDisabled:
            "This server has username and password sign-in turned off."
        case .invalidCredentials:
            "The username or password is wrong."
        case .tooManyAttempts:
            "Too many sign-in attempts. Wait a few minutes and try again."
        case .missingRefreshToken:
            "This server is too old for the app. Update Audiobookshelf and try again."
        case .sessionExpired:
            "Your session has expired. Sign in again."
        case .tokenStorage:
            "Couldn't save your sign-in to the Keychain."
        case .http(let status):
            "The server returned an error (HTTP \(status))."
        case .network(let message):
            message
        case .decoding:
            "The server sent a response the app couldn't read."
        }
    }
}

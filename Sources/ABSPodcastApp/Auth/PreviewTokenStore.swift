#if DEBUG
/// A token store that holds nothing, so SwiftUI previews never touch the real Keychain.
struct PreviewTokenStore: TokenStore {
    func load() throws -> AuthTokens? { nil }
    func save(_ tokens: AuthTokens) throws {}
    func delete() throws {}
}
#endif

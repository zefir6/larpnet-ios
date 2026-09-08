import Foundation

/// Caches the logged-in account's own id so `StatusCard` can tell "is this my post" apart from
/// someone else's -- nothing else in the app tracks this outside `ProfileViewModel.isOwnProfile`,
/// which only applies while actually viewing your own profile screen. Seeded at both app-launch
/// transition points (`LarpnetApp`'s `onLoggedIn` and relaunch `.task`), not from a profile
/// visit -- a fresh login that never visits their own profile would otherwise leave
/// "Block/Report yourself" live on their own posts in Home/Local.
@MainActor
@Observable
final class CurrentAccountStore {
    private(set) var accountId: String?
    private let tokenStore: TokenStore

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        accountId = tokenStore.currentAccountId
    }

    func set(_ id: String?) {
        accountId = id
        tokenStore.currentAccountId = id
    }
}

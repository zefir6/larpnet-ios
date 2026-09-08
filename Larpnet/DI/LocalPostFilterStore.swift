import Foundation

/// Persisted, client-only list of post ids the user has hidden or blocked -- neither concept
/// exists server-side, so this is the sole source of truth. One concrete class, instantiated
/// twice on `AppContainer` (`hiddenPostsStore`, `blockedPostsStore`) with a different
/// `UserDefaults` key -- both instances share the exact same type and operations, so a second
/// near-duplicate class (the way `RecentTagsStore`/`BottomNavOrderStore` are separate concrete
/// classes) would just be copy-pasted boilerplate; those two differ in element type and
/// semantics (LRU-cap-3 strings vs. permutation-validated enum array), this doesn't.
///
/// Stored comma-joined, newest-first (not a bare `Set`) -- the management screens
/// (`LocalPostListView`) list "most recently hidden/blocked first", which a `Set` can't give.
/// `idSet` is exposed for the O(1) membership checks every timeline/thread/profile filter does.
@MainActor
@Observable
final class LocalPostFilterStore {
    private(set) var ids: [String]
    var idSet: Set<String> { Set(ids) }

    private let tokenStore: TokenStore
    private let key: String

    init(tokenStore: TokenStore, key: String) {
        self.tokenStore = tokenStore
        self.key = key
        ids = Self.parse(tokenStore.stringList(for: key))
    }

    func add(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.insert(id, at: 0)
        persist()
    }

    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        persist()
    }

    private func persist() {
        tokenStore.setStringList(ids.joined(separator: ","), for: key)
    }

    // Static, `nonisolated`, and host-independent so this is callable synchronously from a
    // plain (non-`@MainActor`) XCTest method, without touching `UserDefaults.standard` (which
    // `TokenStore` hardcodes) -- `nonisolated` is required because a `static func` on a
    // `@MainActor`-annotated class otherwise inherits that isolation.
    nonisolated static func parse(_ raw: String?) -> [String] {
        raw?.split(separator: ",").map(String.init).filter { !$0.isEmpty } ?? []
    }
}

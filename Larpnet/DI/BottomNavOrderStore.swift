import Foundation

/// Direct port of Android's `ui/nav/BottomNavOrderStore`: persisted, user-reorderable tab
/// sequence, shared between `RootView`'s `TabView` and `SettingsView`'s reorder controls via one
/// `AppContainer`-level instance so both stay in sync without navigating away and back.
@MainActor
@Observable
final class BottomNavOrderStore {
    private(set) var order: [BottomTab]
    private let tokenStore: TokenStore

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        order = Self.readPersisted(tokenStore)
    }

    /// Reorder only, no hide -- `newOrder` must be an exact permutation of every `BottomTab`.
    func setOrder(_ newOrder: [BottomTab]) {
        guard Set(newOrder) == Set(BottomTab.allCases), newOrder.count == BottomTab.allCases.count else { return }
        order = newOrder
        tokenStore.bottomNavOrder = newOrder.map(\.rawValue).joined(separator: ",")
    }

    /// If a future version adds a 6th tab, a stored order from before that update is missing it
    /// -- append anything absent so it doesn't silently disappear for users with an existing
    /// custom order (same fallback as Android's `readPersisted()`).
    private static func readPersisted(_ tokenStore: TokenStore) -> [BottomTab] {
        guard let stored = tokenStore.bottomNavOrder else { return BottomTab.defaultOrder }
        var tabs = stored.split(separator: ",").compactMap { BottomTab(rawValue: String($0)) }
        for tab in BottomTab.allCases where !tabs.contains(tab) {
            tabs.append(tab)
        }
        guard Set(tabs) == Set(BottomTab.allCases) else { return BottomTab.defaultOrder }
        return tabs
    }
}

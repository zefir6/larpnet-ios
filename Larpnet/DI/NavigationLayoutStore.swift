import Foundation

/// Persisted, user-customizable split of every `AppDestination` between the bottom tab bar and
/// the top-left menu -- supersedes `BottomNavOrderStore`, which only ever handled reordering a
/// fixed set of 5 always-shown tabs. Shared between `RootView`'s `TabView`/menu and
/// `SettingsView`'s reorder controls via one `AppContainer`-level instance, same rationale as
/// the store it replaces.
@MainActor
@Observable
final class NavigationLayoutStore {
    private(set) var bottomBar: [AppDestination]
    private(set) var menu: [AppDestination]
    private let tokenStore: TokenStore

    /// The UI blocks moving a destination out of the bar once only this many remain, so the bar
    /// never looks empty/broken.
    static let minimumBottomBarCount = 2

    private static let bottomBarKey = "nav_bottom_bar"
    private static let menuKey = "nav_menu"

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        (bottomBar, menu) = Self.readPersisted(tokenStore)
    }

    /// Reorder only, membership unchanged -- `newOrder` must be an exact permutation of the
    /// current `bottomBar` set. Use `moveToMenu`/`moveToBottomBar` to change which destinations
    /// live where.
    func setBottomBar(_ newOrder: [AppDestination]) {
        guard Set(newOrder) == Set(bottomBar), newOrder.count == bottomBar.count else { return }
        bottomBar = newOrder
        persist()
    }

    func setMenu(_ newOrder: [AppDestination]) {
        guard Set(newOrder) == Set(menu), newOrder.count == menu.count else { return }
        menu = newOrder
        persist()
    }

    /// No-op (rather than clamping or erroring) if this would drop the bar below
    /// `minimumBottomBarCount` -- callers (`SettingsView`'s swipe action) already hide the
    /// action once that floor is reached, this is just the safety net.
    func moveToMenu(_ destination: AppDestination) {
        guard let index = bottomBar.firstIndex(of: destination), bottomBar.count > Self.minimumBottomBarCount else { return }
        bottomBar.remove(at: index)
        menu.append(destination)
        persist()
    }

    func moveToBottomBar(_ destination: AppDestination) {
        guard let index = menu.firstIndex(of: destination) else { return }
        menu.remove(at: index)
        bottomBar.append(destination)
        persist()
    }

    private func persist() {
        tokenStore.setStringList(bottomBar.map(\.rawValue).joined(separator: ","), for: Self.bottomBarKey)
        tokenStore.setStringList(menu.map(\.rawValue).joined(separator: ","), for: Self.menuKey)
    }

    private static func readPersisted(_ tokenStore: TokenStore) -> ([AppDestination], [AppDestination]) {
        if let barRaw = tokenStore.stringList(for: bottomBarKey), let menuRaw = tokenStore.stringList(for: menuKey) {
            let bar = parse(barRaw)
            let menu = parse(menuRaw)
            if isValidPartition(bar: bar, menu: menu) {
                return (bar, menu)
            }
        }

        // One-time migration from the old 5-tab `BottomNavOrderStore` format (`bottom_nav_order`,
        // still readable via `TokenStore.bottomNavOrder`): carry over the relative order of the
        // 4 destinations that still exist as plain tabs, drop `settings` into the menu instead
        // of the bar, and seed the bar's freed-up slot with `profile` -- so an existing user's
        // custom tab arrangement isn't silently reset by this feature.
        if let oldOrder = tokenStore.bottomNavOrder {
            let oldTabs = oldOrder.split(separator: ",").compactMap { AppDestination(rawValue: String($0)) }
            let carried = oldTabs.filter { $0 != .settings }
            if !carried.isEmpty, Set(carried).isSubset(of: [.home, .local, .directory, .notifications]) {
                let bar = carried + [.profile]
                let menu = AppDestination.defaultMenu
                if isValidPartition(bar: bar, menu: menu) {
                    return (bar, menu)
                }
            }
        }

        return (AppDestination.defaultBottomBar, AppDestination.defaultMenu)
    }

    // `static`, `nonisolated`, and host-independent (no `TokenStore`/`UserDefaults` touched) so
    // these are callable synchronously from a plain (non-`@MainActor`) XCTest method -- same
    // rationale as `LocalPostFilterStore.parse`. `nonisolated` is required because a `static
    // func` on a `@MainActor`-annotated class otherwise inherits that isolation.
    nonisolated static func parse(_ raw: String) -> [AppDestination] {
        raw.split(separator: ",").compactMap { AppDestination(rawValue: String($0)) }
    }

    nonisolated static func isValidPartition(bar: [AppDestination], menu: [AppDestination]) -> Bool {
        Set(bar).union(menu) == Set(AppDestination.allCases) && bar.count + menu.count == AppDestination.allCases.count
    }
}

import Foundation

/// Persisted, user-customizable split of every customizable `AppDestination` (see
/// `AppDestination.customizableCases` -- Notifications is fixed, not part of this) between
/// three zones: the bottom tab bar, the top-left bar, and the bottom-right "More" catch-all.
/// Shared between `RootView`'s `TabView`/bars and `SettingsView`'s reorder controls via one
/// `AppContainer`-level instance.
@MainActor
@Observable
final class NavigationLayoutStore {
    enum Zone {
        case bottomBar, topBar, more
    }

    private(set) var bottomBar: [AppDestination]
    private(set) var topBar: [AppDestination]
    private(set) var more: [AppDestination]
    private let tokenStore: TokenStore

    /// The UI blocks moving a destination out of the bar once only this many remain, so the bar
    /// never looks empty/broken.
    static let minimumBottomBarCount = 2

    /// `TabView`'s bottom bar plus the fixed "More" tab (`RootView`) makes for `bottomBar.count +
    /// 1` real tabs. Confirmed live on-device: once that total reaches 6, UIKit's
    /// `UITabBarController` (which `TabView` is built on) auto-collapses to 4 custom tabs plus
    /// its *own* system-generated "More", nesting our tab (and whichever bottom-bar item got
    /// bumped) inside an unwanted extra layer instead of the flat 5-tab bar this app intends.
    /// Capping the bar at 4 keeps the real total at 5 (4 + our own More), safely under that
    /// threshold.
    static let maximumBottomBarCount = 4

    // `_v2` -- a fresh key namespace for the 3-zone shape. Old 2-zone data (`nav_bottom_bar`/
    // `nav_menu`) doesn't map cleanly onto 3 zones (there's no principled way to guess which
    // menu items should become the new top bar vs. More), so this deliberately does not attempt
    // to migrate it field-by-field: an existing customization just resets to the new defaults
    // once, the same as a fresh install. That's an acceptable one-time reset for a UI
    // preference, not user content.
    private static let bottomBarKey = "nav_bottom_bar_v2"
    private static let topBarKey = "nav_top_bar_v2"
    private static let moreKey = "nav_more_v2"

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        (bottomBar, topBar, more) = Self.readPersisted(tokenStore)
    }

    /// Reorder only, membership unchanged -- `newOrder` must be an exact permutation of the
    /// zone's current contents. Use `move(_:to:)` to change which zone a destination lives in.
    func setBottomBar(_ newOrder: [AppDestination]) {
        guard Set(newOrder) == Set(bottomBar), newOrder.count == bottomBar.count else { return }
        bottomBar = newOrder
        persist()
    }

    func setTopBar(_ newOrder: [AppDestination]) {
        guard Set(newOrder) == Set(topBar), newOrder.count == topBar.count else { return }
        topBar = newOrder
        persist()
    }

    func setMore(_ newOrder: [AppDestination]) {
        guard Set(newOrder) == Set(more), newOrder.count == more.count else { return }
        more = newOrder
        persist()
    }

    /// Moves `destination` into `zone`, removing it from whichever zone currently holds it.
    /// No-op (rather than clamping or erroring) if this would drop the bottom bar below
    /// `minimumBottomBarCount` -- callers (`SettingsView`'s swipe actions) already hide that
    /// option once the floor is reached, this is just the safety net.
    func move(_ destination: AppDestination, to zone: Zone) {
        if bottomBar.contains(destination), zone != .bottomBar, bottomBar.count <= Self.minimumBottomBarCount {
            return
        }
        if zone == .bottomBar, !bottomBar.contains(destination), bottomBar.count >= Self.maximumBottomBarCount {
            return
        }
        bottomBar.removeAll { $0 == destination }
        topBar.removeAll { $0 == destination }
        more.removeAll { $0 == destination }
        switch zone {
        case .bottomBar: bottomBar.append(destination)
        case .topBar: topBar.append(destination)
        case .more: more.append(destination)
        }
        persist()
    }

    private func persist() {
        tokenStore.setStringList(bottomBar.map(\.rawValue).joined(separator: ","), for: Self.bottomBarKey)
        tokenStore.setStringList(topBar.map(\.rawValue).joined(separator: ","), for: Self.topBarKey)
        tokenStore.setStringList(more.map(\.rawValue).joined(separator: ","), for: Self.moreKey)
    }

    private static func readPersisted(_ tokenStore: TokenStore) -> ([AppDestination], [AppDestination], [AppDestination]) {
        if let barRaw = tokenStore.stringList(for: bottomBarKey),
           let topRaw = tokenStore.stringList(for: topBarKey),
           let moreRaw = tokenStore.stringList(for: moreKey) {
            let bar = parse(barRaw)
            let top = parse(topRaw)
            let more = parse(moreRaw)
            if isValidPartition(bar: bar, top: top, more: more) {
                return (bar, top, more)
            }
        }
        return (AppDestination.defaultBottomBar, AppDestination.defaultTopBar, AppDestination.defaultMore)
    }

    // `static`, `nonisolated`, and host-independent (no `TokenStore`/`UserDefaults` touched) so
    // these are callable synchronously from a plain (non-`@MainActor`) XCTest method -- same
    // rationale as `LocalPostFilterStore.parse`. `nonisolated` is required because a `static
    // func` on a `@MainActor`-annotated class otherwise inherits that isolation.
    nonisolated static func parse(_ raw: String) -> [AppDestination] {
        raw.split(separator: ",").compactMap { AppDestination(rawValue: String($0)) }
    }

    nonisolated static func isValidPartition(bar: [AppDestination], top: [AppDestination], more: [AppDestination]) -> Bool {
        let all = Set(AppDestination.customizableCases)
        let union = Set(bar).union(top).union(more)
        return union == all && bar.count + top.count + more.count == all.count
    }
}

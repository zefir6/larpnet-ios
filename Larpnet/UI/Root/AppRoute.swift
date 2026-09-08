import Foundation

/// Push-navigation destinations reachable from any bottom-nav tab -- the SwiftUI
/// `NavigationStack` equivalent of Android's shared `NavGraph.kt` route table. Each tab owns
/// its own `NavigationStack` and `[AppRoute]` path, so pushing e.g. a thread from Home doesn't
/// affect the Local tab's back stack, matching Android's per-tab `saveState`/`restoreState`
/// navigation behavior.
enum AppRoute: Hashable {
    case thread(statusId: String)
    case profile(accountId: String?)
    case editProfile
    case search
    case messages
    case newMessage
    case messageThread(accountId: String, conversationId: String?)
    case blockedAccounts
    case hiddenPosts
    case blockedPosts
    case followedThreads
    case hashtag(String)
    case albums
    case album(String)
    /// Pushed when a destination is picked from the top-left menu instead of being the current
    /// tab's own root -- reuses `AppDestination` directly rather than one near-duplicate
    /// `AppRoute` case per destination (`RootView`'s shared `destinationContent(for:path:)`
    /// builds the exact same content either way).
    case destination(AppDestination)
}

/// Compose is presented as a `.sheet`, not a pushed route -- closer to iOS convention for a
/// modal "new item" flow than porting Android's route-based compose screen literally (see plan
/// doc's "Screens & navigation" section).
struct ComposeContext: Identifiable {
    let replyToId: String?
    var id: String { replyToId ?? "new" }
}

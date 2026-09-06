import Foundation

/// Direct port of Android's `ui/compose/RecentTagsStore.kt`: the last 3 hashtags used across any
/// post, most-recent-first, offered as extra toggle chips the next time compose opens. Lives on
/// `AppContainer` rather than `ComposeViewModel` -- the view model is rebuilt from scratch every
/// time the compose sheet is presented (see `RootView`'s `.sheet(item:)`), so a view-model-local
/// store would forget history between posts.
@MainActor
@Observable
final class RecentTagsStore {
    private(set) var recentTags: [String]
    private let tokenStore: TokenStore

    private static let maxCount = 3

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        recentTags = tokenStore.recentTags?
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
    }

    /// Moves `tag` to the front (case-insensitive dedupe against anything already recorded),
    /// then trims to `maxCount`.
    func recordUsed(_ tag: String) {
        var next = recentTags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        next.insert(tag, at: 0)
        recentTags = Array(next.prefix(Self.maxCount))
        tokenStore.recentTags = recentTags.joined(separator: ",")
    }
}

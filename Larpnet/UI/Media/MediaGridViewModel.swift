import Foundation

/// One media attachment paired with the id of the post it came from, so tapping it can open
/// that post's thread.
struct MediaGridItem: Identifiable {
    let statusId: String
    let media: MediaAttachment

    var id: String { media.id }
}

/// A grid of every photo attached to the user's own posts. No dedicated Friendica/Mastodon API
/// exists for this (Friendica's own `Module\Profile\Media` is an HTML web-profile page, not a
/// JSON API route) -- built client-side instead by paginating the user's own statuses (same
/// `getAccountStatuses` call `ProfileViewModel` already uses) and flattening each page's
/// `Status.mediaAttachments`.
@MainActor
@Observable
final class MediaGridViewModel {
    private(set) var items: [MediaGridItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var accountId: String?
    private var nextMaxId: String?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard items.isEmpty, accountId == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let api = try appContainer.friendicaAPI()
            let me = try await api.verifyCredentials()
            accountId = me.id
            let page = try await api.getAccountStatuses(id: me.id)
            items = Self.dedupe(Self.flatten(page.items))
            nextMaxId = page.nextMaxId
            errorMessage = nil
        } catch {
            // A cancelled request (this screen's `.task` gets cancelled if the view disappears
            // mid-load, e.g. navigating away quickly) isn't a real failure worth showing --
            // surfacing it as "network(underlying: "cancelled")" reads as a scary error for what
            // is actually expected, routine behavior.
            guard !Task.isCancelled else { return }
            errorMessage = String(describing: error)
        }
    }

    func loadMore() async {
        guard !isLoadingMore, let accountId, let maxId = nextMaxId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await appContainer.friendicaAPI().getAccountStatuses(id: accountId, maxId: maxId)
            // Deduped against everything already loaded, not just within this page -- a media
            // attachment's `id` doubles as `ForEach`'s row identity in `MediaGridView`, and a
            // duplicate id there is a classic source of SwiftUI misplacing/overlapping views,
            // regardless of how a duplicate could arise (a retried `loadMore()` after a
            // cancelled one landing on the same `maxId`, for instance).
            let existingIds = Set(items.map(\.id))
            items.append(contentsOf: Self.flatten(page.items).filter { !existingIds.contains($0.id) })
            nextMaxId = page.nextMaxId
        } catch {
            // Same rationale as `loadInitial()` -- `MediaGridView` triggers this from a
            // `.task(id:)` on the last grid cell, which `LazyVGrid` routinely cancels when that
            // cell scrolls back out of its virtualized viewport before the request finishes.
            // That's normal scrolling, not a network problem worth alarming the user about.
            guard !Task.isCancelled else { return }
            errorMessage = String(describing: error)
        }
    }

    private static func flatten(_ statuses: [Status]) -> [MediaGridItem] {
        statuses.flatMap { status in
            (status.reblog ?? status).mediaAttachments.map { MediaGridItem(statusId: status.id, media: $0) }
        }
    }

    /// Drops any item whose id repeats earlier in the same list -- see `loadMore()`'s doc
    /// comment for why a duplicate `ForEach` id is worth guarding against defensively.
    private static func dedupe(_ items: [MediaGridItem]) -> [MediaGridItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

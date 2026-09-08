import Foundation

enum TimelineKind {
    case home
    case local
    case hashtag(String)
}

/// Direct port of Android's `ui/timeline/TimelineViewModel.kt`: pull-to-refresh, infinite
/// scroll (Link-header pagination via `nextMaxId`), and 60s-interval polling while the screen
/// is visible that buffers new posts behind a "N new posts" banner rather than reflowing the
/// list under the reader. Optimistic favourite/reblog/bookmark updates mutate local state
/// immediately, then reconcile with the server's returned `Status` on success -- no
/// rollback-on-failure, matching Android.
@MainActor
@Observable
final class TimelineViewModel {
    private(set) var statuses: [Status] = []
    private(set) var pendingNewPosts: [Status] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    private let kind: TimelineKind
    private let appContainer: AppContainer
    private var nextMaxId: String?
    private var pollTask: Task<Void, Never>?

    init(kind: TimelineKind, appContainer: AppContainer) {
        self.kind = kind
        self.appContainer = appContainer
    }

    /// `statuses` filtered against the hidden/blocked local post-id sets -- computed, not
    /// filtered at assignment time, so unhiding/unblocking from the management screens reflects
    /// immediately with no re-fetch. Same `id`-or-`reblog?.id` duality every optimistic-update
    /// method below already uses, since a boost's own id differs from its wrapped status's id.
    var visibleStatuses: [Status] {
        let excluded = appContainer.hiddenPostsStore.idSet.union(appContainer.blockedPostsStore.idSet)
        return statuses.filter { !excluded.contains($0.id) && !(($0.reblog?.id).map(excluded.contains) ?? false) }
    }

    private func fetchPage(maxId: String?, sinceId: String? = nil) async throws -> Page<Status> {
        let api = try appContainer.friendicaAPI()
        switch kind {
        case .home:
            return try await api.homeTimeline(maxId: maxId, sinceId: sinceId)
        case .local:
            return try await api.publicTimeline(maxId: maxId, sinceId: sinceId, local: true)
        case .hashtag(let tag):
            return try await api.hashtagTimeline(tag: tag, maxId: maxId, sinceId: sinceId)
        }
    }

    /// Removes every post by `accountId` from the currently-loaded list -- called right after
    /// blocking that account so their other already-loaded posts disappear immediately, not
    /// just the one post the block action was triggered from. Local-only; the actual
    /// `block(id:)` network call is fired separately by the caller.
    func removeStatuses(byAccount accountId: String) {
        statuses.removeAll { $0.account.id == accountId || $0.reblog?.account.id == accountId }
    }

    func loadInitial() async {
        guard statuses.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await fetchPage(maxId: nil)
            statuses = page.items
            nextMaxId = page.nextMaxId
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func refresh() async {
        do {
            let page = try await fetchPage(maxId: nil)
            statuses = page.items
            nextMaxId = page.nextMaxId
            pendingNewPosts = []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadMore() async {
        guard !isLoadingMore, let maxId = nextMaxId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetchPage(maxId: maxId)
            statuses.append(contentsOf: page.items)
            nextMaxId = page.nextMaxId
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func mergePendingPosts() {
        statuses = pendingNewPosts + statuses
        pendingNewPosts = []
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.pollForNewPosts()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollForNewPosts() async {
        guard let sinceId = statuses.first?.id else { return }
        do {
            let page = try await fetchPage(maxId: nil, sinceId: sinceId)
            guard !page.items.isEmpty else { return }
            let knownIds = Set(pendingNewPosts.map(\.id))
            pendingNewPosts = page.items.filter { !knownIds.contains($0.id) } + pendingNewPosts
        } catch {
            // Silent -- a failed background poll shouldn't surface an error banner over an
            // otherwise-working timeline.
        }
    }

    // MARK: - Optimistic actions
    //
    // These take an `id`, not a `Status` snapshot: the id is stable across renders (unlike a
    // `Status` value, which changes shape the moment it's toggled), so looking up the *current*
    // stored state here -- rather than trusting whatever snapshot the caller happened to close
    // over -- can't go stale. See `Status.==` for the actual bug this UI-level defensiveness was
    // chasing: an id-only equality made SwiftUI treat every toggled status as unchanged and skip
    // re-rendering its row entirely.

    func toggleFavourite(id: String) {
        guard let wasFavourited = currentStatus(id: id)?.favourited else { return }
        apply(id: id) { $0.favourited.toggle(); $0.favouritesCount += $0.favourited ? 1 : -1 }
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (wasFavourited ? api?.unfavourite(id: id) : api?.favourite(id: id))
            if let updated { replace(with: updated) }
        }
    }

    func toggleReblog(id: String) {
        guard let wasReblogged = currentStatus(id: id)?.reblogged else { return }
        apply(id: id) { $0.reblogged.toggle(); $0.reblogsCount += $0.reblogged ? 1 : -1 }
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (wasReblogged ? api?.unreblog(id: id) : api?.reblog(id: id))
            if let updated { replace(with: updated) }
        }
    }

    func toggleBookmark(id: String) {
        guard let wasBookmarked = currentStatus(id: id)?.bookmarked else { return }
        apply(id: id) { $0.bookmarked.toggle() }
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (wasBookmarked ? api?.unbookmark(id: id) : api?.bookmark(id: id))
            if let updated { replace(with: updated) }
        }
    }

    /// `id` may be either a top-level entry's own id or, for a boost, its wrapped `reblog.id` --
    /// `statuses` holds top-level entries whose id differs from a boost's wrapped status.
    private func currentStatus(id: String) -> Status? {
        guard let entry = statuses.first(where: { $0.id == id || $0.reblog?.id == id }) else { return nil }
        return entry.id == id ? entry : entry.reblog
    }

    private func apply(id: String, _ mutate: (inout Status) -> Void) {
        guard let index = statuses.firstIndex(where: { $0.id == id || $0.reblog?.id == id }) else { return }
        if statuses[index].id == id {
            mutate(&statuses[index])
        } else if var reblog = statuses[index].reblog {
            mutate(&reblog)
            statuses[index].reblog = reblog
        }
    }

    private func replace(with status: Status) {
        guard let index = statuses.firstIndex(where: { $0.id == status.id || $0.reblog?.id == status.id }) else { return }
        if statuses[index].id == status.id {
            statuses[index] = status
        } else {
            statuses[index].reblog = status
        }
    }
}

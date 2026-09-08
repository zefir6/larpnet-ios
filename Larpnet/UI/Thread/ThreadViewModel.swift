import Foundation

/// Direct port of Android's `ui/thread/ThreadViewModel.kt`: loads the focus status plus its
/// context (ancestors from the server, flat; descendants reconstructed into a tree via
/// `ThreadBuilder`) and flattens the tree into collapse-aware rows. `tree` is kept (not just its
/// first flattening) as the source of truth for re-flattening on `toggleCollapsed` without a
/// re-fetch. Same optimistic favourite/reblog/bookmark update pattern as `TimelineViewModel`.
@MainActor
@Observable
final class ThreadViewModel {
    private(set) var ancestors: [Status] = []
    private(set) var focus: Status?
    private(set) var descendants: [ThreadRenderItem] = []
    private(set) var collapsedIds: Set<String> = []
    private(set) var isLoading = false
    /// Raw `context.descendants.count` from `load()` -- the total reply count for this thread,
    /// independent of collapse state and of hide/block filtering (both of which change what
    /// `descendants` actually renders). This, not `focus?.repliesCount` or `descendants.count`,
    /// is what gets written to `FollowedThreadsStore` -- see that store's doc comment for why
    /// `repliesCount`'s semantics are unsafe to rely on here.
    private(set) var totalDescendantCount = 0
    var errorMessage: String?

    private var tree: ThreadNode?
    private let statusId: String
    private let appContainer: AppContainer
    /// Accounts blocked from within this thread during the current session -- not persisted
    /// (blocking is server-authoritative; the server excludes the account going forward on its
    /// own), just enough to immediately drop that account's *replies* from view without a
    /// re-fetch. Ancestors and the focus post are deliberately never pruned by this, even if
    /// authored by a blocked account -- same rationale as hide/block-post filtering below: they
    /// are the context the user navigated here to read, and removing one would break the
    /// thread's continuity.
    private var locallyBlockedAccountIds: Set<String> = []

    init(statusId: String, appContainer: AppContainer) {
        self.statusId = statusId
        self.appContainer = appContainer
    }

    var rootStatusId: String? { ancestors.first?.id ?? focus?.id }

    var isFollowingThread: Bool {
        guard let rootStatusId else { return false }
        return appContainer.followedThreadsStore.isFollowing(id: rootStatusId)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = try appContainer.friendicaAPI()
            async let statusTask = api.getStatus(id: statusId)
            async let contextTask = api.getContext(id: statusId)
            let status = try await statusTask
            let context = try await contextTask
            focus = status
            ancestors = context.ancestors.sorted { $0.createdAt < $1.createdAt }
            tree = ThreadBuilder.buildTree(focus: status, descendants: context.descendants)
            totalDescendantCount = context.descendants.count
            collapsedIds = []
            refreshDescendants()
            if let rootStatusId, appContainer.followedThreadsStore.isFollowing(id: rootStatusId) {
                appContainer.followedThreadsStore.markSeen(id: rootStatusId, replyCount: totalDescendantCount)
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleCollapsed(id: String) {
        if collapsedIds.contains(id) { collapsedIds.remove(id) } else { collapsedIds.insert(id) }
        refreshDescendants()
    }

    func toggleFollow() {
        guard let rootStatusId else { return }
        if appContainer.followedThreadsStore.isFollowing(id: rootStatusId) {
            appContainer.followedThreadsStore.unfollow(id: rootStatusId)
        } else {
            appContainer.followedThreadsStore.follow(id: rootStatusId, currentReplyCount: totalDescendantCount)
        }
    }

    /// Drops `accountId`'s replies from `descendants` immediately after blocking them -- see
    /// `locallyBlockedAccountIds`'s doc comment for why ancestors/focus are untouched.
    func removeStatuses(byAccount accountId: String) {
        locallyBlockedAccountIds.insert(accountId)
        refreshDescendants()
    }

    private func refreshDescendants() {
        guard let tree else {
            descendants = []
            return
        }
        let flattened = ThreadBuilder.flatten(tree, collapsedIds: collapsedIds)
        let excludedIds = appContainer.hiddenPostsStore.idSet.union(appContainer.blockedPostsStore.idSet)
        descendants = ThreadBuilder.filterExcluded(
            flattened, excludedStatusIds: excludedIds, excludedAccountIds: locallyBlockedAccountIds
        )
    }

    /// Takes an `id`, not a `Status` snapshot -- see `TimelineViewModel`'s toggle methods for
    /// why (a stale caller-captured `Status` can't be trusted to reflect the just-toggled
    /// state).
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

    private func currentStatus(id: String) -> Status? {
        if let f = focus {
            if f.id == id { return f }
            if let reblog = f.reblog, reblog.id == id { return reblog }
        }
        if let s = ancestors.first(where: { $0.id == id }) { return s }
        if let s = ancestors.first(where: { $0.reblog?.id == id })?.reblog { return s }
        if let s = descendants.first(where: { $0.status.id == id })?.status { return s }
        if let s = descendants.first(where: { $0.status.reblog?.id == id })?.status.reblog { return s }
        return nil
    }

    /// See `TimelineViewModel.apply` -- `id` is the unwrapped status's id, so a boosted
    /// ancestor/descendant/focus needs matching against both its own id and its wrapped
    /// `reblog.id`. Also patches the private `tree` (via `updateTreeStatus`), *before*
    /// re-deriving `descendants` from it below -- `toggleCollapsed` re-flattens straight from
    /// `tree`, so if `tree` weren't kept in sync here, collapsing/expanding an unrelated sibling
    /// branch after a favourite/reblog/bookmark tap would silently revert that tap the next time
    /// `refreshDescendants()` runs.
    private func apply(id: String, _ mutate: (inout Status) -> Void) {
        if var f = focus {
            if f.id == id {
                mutate(&f)
                focus = f
            } else if var reblog = f.reblog, reblog.id == id {
                mutate(&reblog)
                f.reblog = reblog
                focus = f
            }
        }
        if let index = ancestors.firstIndex(where: { $0.id == id }) {
            mutate(&ancestors[index])
        } else if let index = ancestors.firstIndex(where: { $0.reblog?.id == id }) {
            var reblog = ancestors[index].reblog!
            mutate(&reblog)
            ancestors[index].reblog = reblog
        }
        if let tree {
            self.tree = updateTreeStatus(tree, id: id, mutate: mutate)
        }
        refreshDescendants()
    }

    private func updateTreeStatus(_ node: ThreadNode, id: String, mutate: (inout Status) -> Void) -> ThreadNode {
        var status = node.status
        if status.id == id {
            mutate(&status)
        } else if var reblog = status.reblog, reblog.id == id {
            mutate(&reblog)
            status.reblog = reblog
        }
        let children = node.children.map { updateTreeStatus($0, id: id, mutate: mutate) }
        return ThreadNode(status: status, children: children)
    }

    private func replace(with status: Status) {
        apply(id: status.id) { $0 = status }
    }
}

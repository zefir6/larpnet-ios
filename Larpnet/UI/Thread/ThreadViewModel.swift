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
    var errorMessage: String?

    private var tree: ThreadNode?
    private let statusId: String
    private let appContainer: AppContainer

    init(statusId: String, appContainer: AppContainer) {
        self.statusId = statusId
        self.appContainer = appContainer
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
            collapsedIds = []
            refreshDescendants()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleCollapsed(id: String) {
        if collapsedIds.contains(id) { collapsedIds.remove(id) } else { collapsedIds.insert(id) }
        refreshDescendants()
    }

    private func refreshDescendants() {
        guard let tree else {
            descendants = []
            return
        }
        descendants = ThreadBuilder.flatten(tree, collapsedIds: collapsedIds)
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

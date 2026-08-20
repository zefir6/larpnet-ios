import Foundation

/// Direct port of Android's `ui/thread/ThreadViewModel.kt`: loads the focus status plus its
/// context (ancestors from the server, flat; descendants reconstructed into a tree via
/// `ThreadBuilder`) and flattens everything into `(status, depth)` rows for a simple indented
/// list. Same optimistic favourite/reblog/bookmark update pattern as `TimelineViewModel`.
@MainActor
@Observable
final class ThreadViewModel {
    private(set) var ancestors: [Status] = []
    private(set) var focus: Status?
    private(set) var descendantRows: [ThreadRow] = []
    private(set) var isLoading = false
    var errorMessage: String?

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
            let tree = ThreadBuilder.buildTree(focus: status, descendants: context.descendants)
            descendantRows = Array(ThreadBuilder.flatten(tree).dropFirst())
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
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
        if let s = descendantRows.first(where: { $0.status.id == id })?.status { return s }
        if let s = descendantRows.first(where: { $0.status.reblog?.id == id })?.status.reblog { return s }
        return nil
    }

    /// See `TimelineViewModel.apply` -- `id` is the unwrapped status's id, so a boosted
    /// ancestor/descendant/focus needs matching against both its own id and its wrapped
    /// `reblog.id`.
    private func apply(id: String, _ mutate: (inout Status) -> Void) {
        if var f = focus {
            if f.id == id {
                mutate(&f)
                focus = f
                return
            } else if var reblog = f.reblog, reblog.id == id {
                mutate(&reblog)
                f.reblog = reblog
                focus = f
                return
            }
        }
        if let index = ancestors.firstIndex(where: { $0.id == id }) {
            mutate(&ancestors[index])
            return
        }
        if let index = ancestors.firstIndex(where: { $0.reblog?.id == id }) {
            var reblog = ancestors[index].reblog!
            mutate(&reblog)
            ancestors[index].reblog = reblog
            return
        }
        if let index = descendantRows.firstIndex(where: { $0.status.id == id }) {
            var s = descendantRows[index].status
            mutate(&s)
            descendantRows[index] = ThreadRow(status: s, depth: descendantRows[index].depth)
            return
        }
        if let index = descendantRows.firstIndex(where: { $0.status.reblog?.id == id }) {
            var s = descendantRows[index].status
            var reblog = s.reblog!
            mutate(&reblog)
            s.reblog = reblog
            descendantRows[index] = ThreadRow(status: s, depth: descendantRows[index].depth)
        }
    }

    private func replace(with status: Status) {
        apply(id: status.id) { $0 = status }
    }
}

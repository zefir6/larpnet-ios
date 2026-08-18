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

    func toggleFavourite(_ status: Status) {
        apply(status) { $0.favourited.toggle(); $0.favouritesCount += $0.favourited ? 1 : -1 }
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (status.favourited ? api?.unfavourite(id: status.id) : api?.favourite(id: status.id))
            if let updated { replace(with: updated) }
        }
    }

    func toggleReblog(_ status: Status) {
        apply(status) { $0.reblogged.toggle(); $0.reblogsCount += $0.reblogged ? 1 : -1 }
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (status.reblogged ? api?.unreblog(id: status.id) : api?.reblog(id: status.id))
            if let updated { replace(with: updated) }
        }
    }

    func toggleBookmark(_ status: Status) {
        apply(status) { $0.bookmarked.toggle() }
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (status.bookmarked ? api?.unbookmark(id: status.id) : api?.bookmark(id: status.id))
            if let updated { replace(with: updated) }
        }
    }

    private func apply(_ status: Status, _ mutate: (inout Status) -> Void) {
        if focus?.id == status.id, var f = focus {
            mutate(&f)
            focus = f
            return
        }
        if let index = ancestors.firstIndex(where: { $0.id == status.id }) {
            mutate(&ancestors[index])
            return
        }
        if let index = descendantRows.firstIndex(where: { $0.status.id == status.id }) {
            var s = descendantRows[index].status
            mutate(&s)
            descendantRows[index] = ThreadRow(status: s, depth: descendantRows[index].depth)
        }
    }

    private func replace(with status: Status) {
        apply(status) { $0 = status }
    }
}

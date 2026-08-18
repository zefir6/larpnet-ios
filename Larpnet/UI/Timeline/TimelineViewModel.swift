import Foundation

enum TimelineKind {
    case home
    case local
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

    private func fetchPage(maxId: String?, sinceId: String? = nil) async throws -> Page<Status> {
        let api = try appContainer.friendicaAPI()
        switch kind {
        case .home:
            return try await api.homeTimeline(maxId: maxId, sinceId: sinceId)
        case .local:
            return try await api.publicTimeline(maxId: maxId, sinceId: sinceId, local: true)
        }
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
        guard let index = statuses.firstIndex(where: { $0.id == status.id }) else { return }
        mutate(&statuses[index])
    }

    private func replace(with status: Status) {
        guard let index = statuses.firstIndex(where: { $0.id == status.id }) else { return }
        statuses[index] = status
    }
}

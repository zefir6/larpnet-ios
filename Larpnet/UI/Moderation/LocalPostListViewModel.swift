import Foundation

/// One row in a Hidden/Blocked Posts list -- `status` is `nil` when `getStatus(id:)` 404s (the
/// post was deleted upstream since it was hidden/blocked). The id is kept and rendered as an
/// "unavailable" placeholder rather than silently dropped, or that id becomes a permanently
/// stuck, unremovable entry in the persisted store.
struct LocalPostListEntry: Identifiable {
    let id: String
    var status: Status?
}

/// Renders a `LocalPostFilterStore`'s ids as re-fetched posts with an unhide/unblock action.
/// One reusable pair for both the Hidden Posts and Blocked Posts screens, parameterized by which
/// store it targets -- same "one class, two instantiations" reasoning as
/// `LocalPostFilterStore` itself.
@MainActor
@Observable
final class LocalPostListViewModel {
    private(set) var entries: [LocalPostListEntry] = []
    private(set) var isLoading = false

    private let store: LocalPostFilterStore
    private let appContainer: AppContainer

    /// Fetched in bounded batches, not one `TaskGroup` per id at a time and not N sequential
    /// awaits -- a long-lived hidden/blocked list shouldn't fire an unbounded burst of
    /// concurrent requests.
    private static let batchSize = 8

    init(store: LocalPostFilterStore, appContainer: AppContainer) {
        self.store = store
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let ids = store.ids
        guard let api = try? appContainer.friendicaAPI() else {
            entries = ids.map { LocalPostListEntry(id: $0, status: nil) }
            return
        }
        var fetched: [String: Status] = [:]
        var index = 0
        while index < ids.count {
            let batch = ids[index..<min(index + Self.batchSize, ids.count)]
            await withTaskGroup(of: (String, Status?).self) { group in
                for id in batch {
                    group.addTask {
                        (id, try? await api.getStatus(id: id))
                    }
                }
                for await (id, status) in group {
                    fetched[id] = status
                }
            }
            index += Self.batchSize
        }
        entries = store.ids.map { LocalPostListEntry(id: $0, status: fetched[$0]) }
    }

    func remove(_ id: String) {
        store.remove(id)
        entries.removeAll { $0.id == id }
    }
}

import Foundation

/// One row on the Following screen -- the followed thread's root status (for rendering) plus
/// whether it has replies the user hasn't seen yet.
struct FollowedThreadEntry: Identifiable {
    let id: String
    var status: Status?
    var hasUnread: Bool
}

/// Lists followed threads with an unread-reply badge. No server concept for "watch a thread"
/// exists, so this is entirely driven by `FollowedThreadsStore` (persisted ids +
/// last-seen-reply-count) cross-checked against each thread's current state.
@MainActor
@Observable
final class FollowedThreadsViewModel {
    private(set) var entries: [FollowedThreadEntry] = []
    private(set) var isLoading = false

    private let appContainer: AppContainer
    private static let batchSize = 8

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let followed = appContainer.followedThreadsStore.followed
        guard let api = try? appContainer.friendicaAPI() else {
            entries = followed.map { FollowedThreadEntry(id: $0.rootStatusId, status: nil, hasUnread: false) }
            return
        }
        var results: [String: (Status?, Int?)] = [:]
        var index = 0
        while index < followed.count {
            let batch = followed[index..<min(index + Self.batchSize, followed.count)]
            await withTaskGroup(of: (String, Status?, Int?).self) { group in
                for entry in batch {
                    group.addTask {
                        // Both calls target the same root id: `getStatus` to render the row,
                        // `getContext` for its raw `descendants.count` -- the same unambiguous
                        // "total replies" metric `ThreadViewModel.totalDescendantCount` uses, not
                        // `Status.repliesCount` (see `FollowedThreadsStore`'s doc comment).
                        async let statusTask = try? api.getStatus(id: entry.rootStatusId)
                        async let contextTask = try? api.getContext(id: entry.rootStatusId)
                        let status = await statusTask
                        let context = await contextTask
                        return (entry.rootStatusId, status, context?.descendants.count)
                    }
                }
                for await (id, status, replyCount) in group {
                    results[id] = (status, replyCount)
                }
            }
            index += Self.batchSize
        }
        entries = followed.map { entry in
            let (status, replyCount) = results[entry.rootStatusId] ?? (nil, nil)
            let hasUnread = (replyCount ?? entry.lastSeenReplyCount) > entry.lastSeenReplyCount
            return FollowedThreadEntry(id: entry.rootStatusId, status: status, hasUnread: hasUnread)
        }
    }

    func unfollow(_ id: String) {
        appContainer.followedThreadsStore.unfollow(id: id)
        entries.removeAll { $0.id == id }
    }
}

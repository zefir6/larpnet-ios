import Foundation

/// One followed thread: the root status id plus the reply count last seen by the user, used to
/// compute the "N new replies" badge on the Following screen.
///
/// `lastSeenReplyCount`/whatever is compared against it must always be
/// `StatusContext.descendants.count` (the raw count from `getContext(id:)`), never
/// `Status.repliesCount` -- that field's semantics (direct replies only vs. whole-subtree) are
/// unconfirmed against larpnet.pl, and using it risks a badge that silently never fires for a
/// reply-to-a-reply. `descendants.count` is unambiguous: it's literally every post in the
/// thread below the root, however nested.
struct FollowedThread: Codable, Sendable, Hashable {
    var rootStatusId: String
    var lastSeenReplyCount: Int
    var followedAt: Double
}

/// Persisted watchlist of threads the user wants to track for new replies -- no server concept
/// exists for this (only account-follow does), so this is 100% client-side. Needs structured
/// per-entry state (not just an id), so this is JSON in one `UserDefaults` key rather than the
/// comma-joined-string convention `RecentTagsStore`/`LocalPostFilterStore` use.
@MainActor
@Observable
final class FollowedThreadsStore {
    private(set) var followed: [FollowedThread]
    private let tokenStore: TokenStore

    // Dedicated plain coder -- never `FriendicaJSON.decoder`/`encoder`, which is tuned for
    // server responses (a custom ISO8601-with-fractional-seconds date strategy) and has no
    // reason to touch purely local Codable round-tripping. `followedAt` is a plain `Double`
    // (Unix timestamp) rather than `Date` for the same reason: no ambiguity about which coder
    // produced/consumes it.
    private nonisolated static let encoder = JSONEncoder()
    private nonisolated static let decoder = JSONDecoder()

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        followed = Self.parse(tokenStore.followedThreadsJSON)
    }

    func isFollowing(id: String) -> Bool {
        followed.contains { $0.rootStatusId == id }
    }

    func follow(id: String, currentReplyCount: Int) {
        guard !isFollowing(id: id) else { return }
        followed.insert(
            FollowedThread(rootStatusId: id, lastSeenReplyCount: currentReplyCount, followedAt: Date().timeIntervalSince1970),
            at: 0
        )
        persist()
    }

    func unfollow(id: String) {
        followed.removeAll { $0.rootStatusId == id }
        persist()
    }

    func markSeen(id: String, replyCount: Int) {
        guard let index = followed.firstIndex(where: { $0.rootStatusId == id }) else { return }
        followed[index].lastSeenReplyCount = replyCount
        persist()
    }

    func lastSeenReplyCount(for id: String) -> Int? {
        followed.first { $0.rootStatusId == id }?.lastSeenReplyCount
    }

    private func persist() {
        guard let data = try? Self.encoder.encode(followed) else { return }
        tokenStore.followedThreadsJSON = String(data: data, encoding: .utf8)
    }

    // Static, `nonisolated`, and host-independent so this is callable synchronously from a
    // plain (non-`@MainActor`) XCTest method, without touching `UserDefaults.standard` --
    // `nonisolated` is required because a `static func` on a `@MainActor`-annotated class
    // otherwise inherits that isolation.
    nonisolated static func parse(_ raw: String?) -> [FollowedThread] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? decoder.decode([FollowedThread].self, from: data)) ?? []
    }
}

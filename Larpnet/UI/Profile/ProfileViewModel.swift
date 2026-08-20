import Foundation

/// Direct port of Android's `ui/profile/ProfileViewModel.kt`: own account (`accountId == nil`)
/// or another account's profile, header + statuses list, follow/unfollow,
/// favourite/reblog/bookmark/delete on posts.
@MainActor
@Observable
final class ProfileViewModel {
    private(set) var account: Account?
    private(set) var relationship: Relationship?
    private(set) var statuses: [Status] = []
    private(set) var isLoading = false
    var errorMessage: String?

    let accountId: String?
    let isOwnProfile: Bool
    private let appContainer: AppContainer
    private var nextMaxId: String?

    init(accountId: String?, appContainer: AppContainer) {
        self.accountId = accountId
        self.isOwnProfile = accountId == nil
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = try appContainer.friendicaAPI()
            let resolvedAccount: Account
            if let accountId {
                resolvedAccount = try await api.getAccount(id: accountId)
            } else {
                resolvedAccount = try await api.verifyCredentials()
            }
            account = resolvedAccount
            let page = try await api.getAccountStatuses(id: resolvedAccount.id)
            statuses = page.items
            nextMaxId = page.nextMaxId
            if !isOwnProfile {
                relationship = try await api.relationships(ids: [resolvedAccount.id]).first
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadMore() async {
        guard let maxId = nextMaxId, let account else { return }
        do {
            let page = try await appContainer.friendicaAPI().getAccountStatuses(id: account.id, maxId: maxId)
            statuses.append(contentsOf: page.items)
            nextMaxId = page.nextMaxId
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleFollow() {
        guard let account, var relationship else { return }
        let wasFollowing = relationship.following
        relationship.following.toggle()
        self.relationship = relationship
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (wasFollowing ? api?.unfollow(id: account.id) : api?.follow(id: account.id))
            if let updated { self.relationship = updated }
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

    func delete(_ status: Status) {
        statuses.removeAll { $0.id == status.id }
        Task { try? await appContainer.friendicaAPI().deleteStatus(id: status.id) }
    }

    /// See `TimelineViewModel.apply` -- `id` is the unwrapped status's id, but `statuses` holds
    /// top-level entries whose id differs from a boost's wrapped `reblog.id`.
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

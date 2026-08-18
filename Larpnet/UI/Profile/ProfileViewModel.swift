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

    func delete(_ status: Status) {
        statuses.removeAll { $0.id == status.id }
        Task { try? await appContainer.friendicaAPI().deleteStatus(id: status.id) }
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

import Foundation

/// Segmented view of the logged-in account's connections: pending incoming follow requests
/// (default/first segment -- "requests on top"), people you follow, people who follow you, and
/// people who follow you but you don't follow back. Each segment keeps its own independent
/// pagination state (`SegmentState`) so switching segments doesn't discard progress. "Not
/// following back" has no dedicated endpoint -- it's a client-side filter over the Followers
/// segment's already-loaded page, cross-referenced against `relationshipsByAccountId`.
@MainActor
@Observable
final class ContactsViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case requests, following, followers, notFollowingBack

        var id: String { rawValue }

        var label: String {
            switch self {
            case .requests: "Requests"
            case .following: "Following"
            case .followers: "Followers"
            case .notFollowingBack: "Not following back"
            }
        }
    }

    private struct SegmentState {
        var accounts: [Account] = []
        var nextMaxId: String?
        var isLoading = false
        var isLoadingMore = false
        var loadedOnce = false
    }

    var selectedFilter: Filter = .requests
    private(set) var relationshipsByAccountId: [String: Relationship] = [:]
    var errorMessage: String?

    private let appContainer: AppContainer
    private var segments: [Filter: SegmentState] = [:]

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    var accounts: [Account] {
        switch selectedFilter {
        case .notFollowingBack:
            return (segments[.followers]?.accounts ?? [])
                .filter { relationshipsByAccountId[$0.id]?.following != true }
        default:
            return segments[selectedFilter]?.accounts ?? []
        }
    }

    var isLoading: Bool { segments[backingFilter]?.isLoading ?? false }
    var isLoadingMore: Bool { segments[backingFilter]?.isLoadingMore ?? false }

    /// "Not following back" rides on the Followers segment's data -- there's no separate endpoint.
    private var backingFilter: Filter {
        selectedFilter == .notFollowingBack ? .followers : selectedFilter
    }

    func loadIfNeeded() async {
        let filter = backingFilter
        guard segments[filter]?.loadedOnce != true else { return }
        segments[filter, default: SegmentState()].isLoading = true
        await fetchPage(filter: filter, maxId: nil, append: false)
    }

    func loadMore() async {
        let filter = backingFilter
        guard let maxId = segments[filter]?.nextMaxId, segments[filter]?.isLoadingMore != true else { return }
        segments[filter, default: SegmentState()].isLoadingMore = true
        await fetchPage(filter: filter, maxId: maxId, append: true)
    }

    private func fetchPage(filter: Filter, maxId: String?, append: Bool) async {
        do {
            let api = try appContainer.friendicaAPI()
            let page = try await page(for: filter, api: api, maxId: maxId)
            if append {
                segments[filter, default: SegmentState()].accounts.append(contentsOf: page.items)
            } else {
                segments[filter, default: SegmentState()].accounts = page.items
            }
            segments[filter]?.nextMaxId = page.nextMaxId
            segments[filter]?.isLoading = false
            segments[filter]?.isLoadingMore = false
            segments[filter]?.loadedOnce = true
            if !page.items.isEmpty {
                let relationships = try await api.relationships(ids: page.items.map(\.id))
                for relationship in relationships {
                    relationshipsByAccountId[relationship.id] = relationship
                }
            }
            errorMessage = nil
        } catch {
            segments[filter]?.isLoading = false
            segments[filter]?.isLoadingMore = false
            errorMessage = String(describing: error)
        }
    }

    private func page(for filter: Filter, api: FriendicaAPIClient, maxId: String?) async throws -> Page<Account> {
        switch filter {
        case .requests:
            return try await api.followRequests(maxId: maxId)
        case .following:
            guard let id = appContainer.currentAccountStore.accountId else {
                return Page(items: [], nextMaxId: nil, prevMinId: nil)
            }
            return try await api.following(id: id, maxId: maxId)
        case .followers, .notFollowingBack:
            guard let id = appContainer.currentAccountStore.accountId else {
                return Page(items: [], nextMaxId: nil, prevMinId: nil)
            }
            return try await api.followers(id: id, maxId: maxId)
        }
    }

    func unfollow(_ account: Account) {
        segments[.following]?.accounts.removeAll { $0.id == account.id }
        relationshipsByAccountId[account.id]?.following = false
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            _ = try? await api.unfollow(id: account.id)
        }
    }

    func follow(_ account: Account) {
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            if let updated = try? await api.follow(id: account.id) {
                relationshipsByAccountId[account.id] = updated
            }
        }
    }

    func accept(_ account: Account) {
        removeRequest(account)
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            try? await FollowRequestActions.accept(account, api: api)
        }
    }

    func acceptAndFollowBack(_ account: Account) {
        removeRequest(account)
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            try? await FollowRequestActions.acceptAndFollowBack(account, api: api)
        }
    }

    func decline(_ account: Account) {
        removeRequest(account)
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            try? await FollowRequestActions.decline(account, api: api)
        }
    }

    private func removeRequest(_ account: Account) {
        segments[.requests]?.accounts.removeAll { $0.id == account.id }
    }
}

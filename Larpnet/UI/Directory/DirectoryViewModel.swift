import Foundation

/// Direct port of Android's `ui/directory/DirectoryViewModel.kt`: paginated (offset-based, no
/// Link header) list of local instance accounts with follow buttons.
@MainActor
@Observable
final class DirectoryViewModel {
    private(set) var accounts: [Account] = []
    private(set) var relationshipsByAccountId: [String: Relationship] = [:]
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var offset = 0
    private var reachedEnd = false
    private static let pageSize = 40

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard accounts.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await fetchNextPage()
    }

    func loadMore() async {
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetchNextPage()
    }

    private func fetchNextPage() async {
        do {
            let api = try appContainer.friendicaAPI()
            let page = try await api.directory(offset: offset, limit: Self.pageSize)
            reachedEnd = page.count < Self.pageSize
            offset += page.count
            accounts.append(contentsOf: page)
            if !page.isEmpty {
                let relationships = try await api.relationships(ids: page.map(\.id))
                for relationship in relationships {
                    relationshipsByAccountId[relationship.id] = relationship
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleFollow(_ account: Account) {
        let wasFollowing = relationshipsByAccountId[account.id]?.following ?? false
        Task {
            let api = try? appContainer.friendicaAPI()
            let updated = try? await (wasFollowing ? api?.unfollow(id: account.id) : api?.follow(id: account.id))
            if let updated { relationshipsByAccountId[account.id] = updated }
        }
    }
}

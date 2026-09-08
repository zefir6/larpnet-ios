import Foundation

/// Lists accounts blocked via `POST /api/v1/accounts/:id/block` (from `StatusCard`'s moderation
/// menu or here directly), sourced from `GET /api/v1/blocks` -- server-authoritative, so no
/// local persistence needed. Link-header paginated, same shape as `getAccountStatuses`/
/// `followers`, unlike `DirectoryViewModel`'s offset-based paging.
@MainActor
@Observable
final class BlockedAccountsViewModel {
    private(set) var accounts: [Account] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var nextMaxId: String?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard accounts.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await appContainer.friendicaAPI().blockedAccounts()
            accounts = page.items
            nextMaxId = page.nextMaxId
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
            let page = try await appContainer.friendicaAPI().blockedAccounts(maxId: maxId)
            accounts.append(contentsOf: page.items)
            nextMaxId = page.nextMaxId
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func unblock(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        Task { try? await appContainer.friendicaAPI().unblock(id: account.id) }
    }
}

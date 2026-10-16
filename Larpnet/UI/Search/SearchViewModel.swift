import Foundation

/// Direct port of Android's `ui/search/SearchViewModel.kt`: 300ms debounced account search,
/// single page only (no Link header on this endpoint).
@MainActor
@Observable
final class SearchViewModel {
    var query: String = "" {
        didSet { scheduleSearch() }
    }
    private(set) var results: [Account] = []
    private(set) var isSearching = false
    var errorMessage: String?

    /// Local DM partners ranked by recency, loaded once when "start new chat" opens (see
    /// `loadSuggestedContactsIfNeeded()`) -- not reloaded per keystroke. Shown as "Suggested"
    /// before the user types, and used to instantly narrow results for the first keystrokes
    /// while `scheduleSearch()`'s debounced server call is still in flight.
    private(set) var suggestedAccounts: [Account] = []
    private var suggestionsLoaded = false

    private let appContainer: AppContainer
    private var searchTask: Task<Void, Never>?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    /// Call from the chat-recipient picker only (`SearchView.task`) -- a no-op on every call
    /// after the first, so re-appearing doesn't re-fetch or reorder the list under the user.
    func loadSuggestedContactsIfNeeded() {
        guard !suggestionsLoaded else { return }
        suggestionsLoaded = true
        Task { [weak self] in
            guard let self else { return }
            let nicknames = await appContainer.matrixClientStore.suggestedDirectChatNicknames()
            guard !nicknames.isEmpty else { return }
            let resolved = await withTaskGroup(of: Account?.self) { group in
                for nickname in nicknames {
                    group.addTask { await self.resolveAccount(nickname: nickname) }
                }
                var accounts: [Account] = []
                for await account in group where account != nil {
                    accounts.append(account!)
                }
                return accounts
            }
            // The task group above doesn't preserve call order -- restore the original
            // recency ranking `suggestedDirectChatNicknames()` already computed.
            let rank = Dictionary(uniqueKeysWithValues: nicknames.enumerated().map { ($1, $0) })
            suggestedAccounts = resolved.sorted {
                (rank[$0.username] ?? .max) < (rank[$1.username] ?? .max)
            }
        }
    }

    /// No dedicated lookup-by-nickname endpoint exists in this API client, so this reuses the
    /// fuzzy search and picks the exact username match rather than trusting the search ranking
    /// -- a nickname collision with a longer/similar name elsewhere would otherwise resolve to
    /// the wrong account.
    private func resolveAccount(nickname: String) async -> Account? {
        guard let api = try? appContainer.friendicaAPI() else { return nil }
        let candidates = (try? await api.searchAccounts(query: nickname, limit: 5)) ?? []
        return candidates.first { $0.username.caseInsensitiveCompare(nickname) == .orderedSame }
    }

    /// Instant local narrowing of the already-loaded suggested list, shown immediately on every
    /// keystroke while the debounced server search is still pending -- so the picker doesn't
    /// look frozen for `scheduleSearch()`'s 300ms.
    var filteredSuggestedAccounts: [Account] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return suggestedAccounts }
        return suggestedAccounts.filter {
            $0.username.localizedCaseInsensitiveContains(trimmed)
                || $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.search(trimmed)
        }
    }

    private func search(_ query: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let api = try appContainer.friendicaAPI()
            results = try await api.searchAccounts(query: query)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

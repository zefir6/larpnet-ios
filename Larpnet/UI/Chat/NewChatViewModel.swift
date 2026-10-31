import Foundation

/// Backs `NewChatView`. Mirrors the web client's `ContactPicker`: before the user types, show
/// recent 1:1 chat partners and then everyone on Larpnet, so there's always someone to pick;
/// while typing, filter that list instantly and merge in the debounced server search.
@MainActor
@Observable
final class NewChatViewModel {
    var query: String = "" {
        didSet { scheduleSearch() }
    }
    /// Recent 1:1 partners, newest first (`MatrixClientStore.recentDirectChatNicknames()`).
    private(set) var recent: [Account] = []
    /// Local directory, minus anyone already in `recent`.
    private(set) var everyone: [Account] = []
    private(set) var searchResults: [Account] = []
    private(set) var isLoading = false
    private(set) var isSearching = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var searchTask: Task<Void, Never>?
    private var loaded = false

    /// Directory pages are fetched until a short page or this cap -- Larpnet is one
    /// community, so this covers everyone without paging UI.
    private static let directoryPageSize = 80
    private static let directoryCap = 400

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    var queryIsBlank: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Instant local matches first, then server results not already shown. Remote accounts
    /// (`acct` with `@domain`) are dropped: only local users have a Matrix identity.
    var matches: [Account] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let local = (recent + everyone).filter {
            $0.username.localizedCaseInsensitiveContains(trimmed)
                || $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
        let seen = Set(local.map(\.id))
        return local + searchResults.filter { !$0.acct.contains("@") && !seen.contains($0.id) }
    }

    /// Once per screen -- re-appearing (e.g. back from a profile) doesn't reload or reorder.
    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        isLoading = true
        defer { isLoading = false }

        async let recentNicknames = appContainer.matrixClientStore.recentDirectChatNicknames()
        async let me = try? appContainer.friendicaAPI().verifyCredentials()
        let ownId = await me?.id
        // Chatting with yourself isn't a thing; the directory includes your own profile.
        let directory = await loadDirectory().filter { $0.id != ownId }
        let nicknames = await recentNicknames

        let byNickname = Dictionary(
            directory.map { ($0.username.lowercased(), $0) }, uniquingKeysWith: { first, _ in first }
        )
        var recentAccounts: [Account] = []
        for nickname in nicknames {
            if let account = byNickname[nickname] {
                recentAccounts.append(account)
            } else if let account = await resolveAccount(nickname: nickname) {
                // Not in the directory (profile not published) but still a chat partner.
                recentAccounts.append(account)
            }
        }
        let recentIds = Set(recentAccounts.map(\.id))
        recent = recentAccounts
        everyone = directory
            .filter { !recentIds.contains($0.id) }
            .sorted { Self.sortName($0).localizedCaseInsensitiveCompare(Self.sortName($1)) == .orderedAscending }
    }

    private func loadDirectory() async -> [Account] {
        guard let api = try? appContainer.friendicaAPI() else { return [] }
        var accounts: [Account] = []
        while accounts.count < Self.directoryCap {
            do {
                let page = try await api.directory(offset: accounts.count, limit: Self.directoryPageSize, local: true)
                accounts += page
                if page.count < Self.directoryPageSize { break }
            } catch {
                errorMessage = String(describing: error)
                break
            }
        }
        return accounts.filter { !$0.acct.contains("@") }
    }

    private func resolveAccount(nickname: String) async -> Account? {
        guard let api = try? appContainer.friendicaAPI(),
              let account = try? await api.lookupLocalAccount(nickname: nickname),
              !account.acct.contains("@") else { return nil }
        return account
    }

    private static func sortName(_ account: Account) -> String {
        account.displayName.isEmpty ? account.username : account.displayName
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        // Set before the debounce so the view shows a spinner, not "No one found", meanwhile.
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.search(trimmed)
        }
    }

    private func search(_ query: String) async {
        do {
            let api = try appContainer.friendicaAPI()
            let results = try await api.searchAccounts(query: query)
            // A newer keystroke has scheduled its own search; let that one finish the spinner.
            guard !Task.isCancelled else { return }
            searchResults = results
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = String(describing: error)
        }
        isSearching = false
    }
}

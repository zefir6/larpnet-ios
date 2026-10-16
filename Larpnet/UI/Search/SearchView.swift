import SwiftUI

/// Doubles as the "pick a DM recipient" screen via `onSelectAccount`, same as Android's
/// `SearchScreen` (used both from the bottom-nav search entry point and from "New Message").
///
/// `chatRecipientMode` scopes this to picking a Matrix chat partner rather than a general
/// profile lookup: `accounts/search` searches the whole known fediverse by default, but Matrix
/// identities only exist for *local* Larpnet accounts (see `MatrixClientStore.
/// openOrCreateDirectRoom(nickname:)`), so a remote result here could never actually start a
/// chat -- filtered client-side (no `local`-only param exists on the search endpoint, unlike
/// `directory`) by the Mastodon-API convention that a local account's `acct` has no `@domain`
/// suffix. Also offers a direct "enter a Matrix address" fallback for someone who already knows
/// the exact address (including a federated one on a different homeserver, which the directory
/// search couldn't find anyway).
struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @State private var customAddress = ""
    let onOpenProfile: (String) -> Void
    var onSelectAccount: ((Account) -> Void)?
    var chatRecipientMode = false
    var onEnterMatrixAddress: ((String) -> Void)?

    init(
        appContainer: AppContainer, onOpenProfile: @escaping (String) -> Void,
        onSelectAccount: ((Account) -> Void)? = nil,
        chatRecipientMode: Bool = false,
        onEnterMatrixAddress: ((String) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: SearchViewModel(appContainer: appContainer))
        self.onOpenProfile = onOpenProfile
        self.onSelectAccount = onSelectAccount
        self.chatRecipientMode = chatRecipientMode
        self.onEnterMatrixAddress = onEnterMatrixAddress
    }

    private var queryIsBlank: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var query: String { viewModel.query }

    /// While typing, instant local matches from the already-loaded suggested list come first
    /// (deduped against the debounced server results, which land ~300ms later) so frequently-
    /// chatted-with contacts surface first and the list never looks frozen while waiting on the
    /// network. With a blank query this isn't used -- the dedicated "Suggested" section below
    /// covers that case instead.
    private var displayedResults: [Account] {
        guard chatRecipientMode else { return viewModel.results }
        let suggestedMatches = viewModel.filteredSuggestedAccounts
        let localResults = viewModel.results.filter { !$0.acct.contains("@") }
        let suggestedIds = Set(suggestedMatches.map(\.id))
        return suggestedMatches + localResults.filter { !suggestedIds.contains($0.id) }
    }

    var body: some View {
        List {
            if chatRecipientMode {
                Section("Or enter a Matrix address") {
                    TextField("@user:server", text: $customAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Start chat") {
                        let trimmed = customAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onEnterMatrixAddress?(trimmed)
                    }
                    .disabled(customAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if chatRecipientMode, queryIsBlank, !viewModel.suggestedAccounts.isEmpty {
                Section("Suggested") {
                    ForEach(viewModel.suggestedAccounts) { account in
                        accountRow(account)
                    }
                }
            } else {
                ForEach(displayedResults) { account in
                    accountRow(account)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .searchable(text: $viewModel.query, prompt: chatRecipientMode ? "Search Larpnet users" : "Search accounts")
        .overlay {
            if viewModel.isSearching, displayedResults.isEmpty, !queryIsBlank {
                ProgressView()
            }
        }
        .navigationTitle("Search")
        .task {
            if chatRecipientMode { viewModel.loadSuggestedContactsIfNeeded() }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        Button {
            if let onSelectAccount {
                onSelectAccount(account)
            } else {
                onOpenProfile(account.id)
            }
        } label: {
            AccountRow(account: account)
        }
        .buttonStyle(.plain)
    }
}

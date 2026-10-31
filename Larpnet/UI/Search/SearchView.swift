import SwiftUI

/// Doubles as the "pick a DM recipient" screen via `onSelectAccount`, same as Android's
/// `SearchScreen` (used both from the bottom-nav search entry point and from "New Message").
/// Chat recipients have their own picker, `NewChatView`.
struct SearchView: View {
    @State private var viewModel: SearchViewModel
    let onOpenProfile: (String) -> Void
    var onSelectAccount: ((Account) -> Void)?

    init(
        appContainer: AppContainer, onOpenProfile: @escaping (String) -> Void,
        onSelectAccount: ((Account) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: SearchViewModel(appContainer: appContainer))
        self.onOpenProfile = onOpenProfile
        self.onSelectAccount = onSelectAccount
    }

    var body: some View {
        List {
            ForEach(viewModel.results) { account in
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        // `.always`: with an inline title the default placement hides the field until the
        // list is pulled down, leaving an empty-looking screen.
        .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search accounts")
        .overlay {
            if viewModel.isSearching, viewModel.results.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

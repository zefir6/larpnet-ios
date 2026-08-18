import SwiftUI

/// Doubles as the "pick a DM recipient" screen via `onSelectAccount`, same as Android's
/// `SearchScreen` (used both from the bottom-nav search entry point and from "New Message").
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
        .searchable(text: $viewModel.query, prompt: "Search accounts")
        .overlay {
            if viewModel.isSearching, viewModel.results.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Search")
    }
}

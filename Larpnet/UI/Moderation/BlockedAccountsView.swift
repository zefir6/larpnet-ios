import SwiftUI

struct BlockedAccountsView: View {
    @State private var viewModel: BlockedAccountsViewModel

    init(appContainer: AppContainer) {
        _viewModel = State(initialValue: BlockedAccountsViewModel(appContainer: appContainer))
    }

    var body: some View {
        List {
            ForEach(viewModel.accounts) { account in
                HStack {
                    AccountRow(account: account)
                    Spacer(minLength: 8)
                    Button("Unblock") { viewModel.unblock(account) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .onAppear {
                    if account.id == viewModel.accounts.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
            if viewModel.accounts.isEmpty, !viewModel.isLoading, viewModel.errorMessage == nil {
                Text("No blocked users.")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.accounts.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadInitial() }
    }
}

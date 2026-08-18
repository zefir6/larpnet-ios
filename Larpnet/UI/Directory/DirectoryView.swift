import SwiftUI

struct DirectoryView: View {
    @State private var viewModel: DirectoryViewModel
    let onOpenProfile: (String) -> Void

    init(appContainer: AppContainer, onOpenProfile: @escaping (String) -> Void) {
        _viewModel = State(initialValue: DirectoryViewModel(appContainer: appContainer))
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        List {
            ForEach(viewModel.accounts) { account in
                HStack {
                    Button { onOpenProfile(account.id) } label: {
                        AccountRow(account: account)
                    }
                    .buttonStyle(.plain)
                    if let relationship = viewModel.relationshipsByAccountId[account.id] {
                        Button(relationship.following ? "Unfollow" : "Follow") {
                            viewModel.toggleFollow(account)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .onAppear {
                    if account.id == viewModel.accounts.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
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
        .task { await viewModel.loadInitial() }
    }
}

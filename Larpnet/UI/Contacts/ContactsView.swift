import SwiftUI

struct ContactsView: View {
    @State private var viewModel: ContactsViewModel
    let onOpenProfile: (String) -> Void

    init(appContainer: AppContainer, onOpenProfile: @escaping (String) -> Void) {
        _viewModel = State(initialValue: ContactsViewModel(appContainer: appContainer))
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $viewModel.selectedFilter) {
                ForEach(ContactsViewModel.Filter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            List {
                ForEach(viewModel.accounts) { account in
                    row(for: account)
                        .onAppear {
                            if account.id == viewModel.accounts.last?.id {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
                if viewModel.accounts.isEmpty, !viewModel.isLoading, viewModel.errorMessage == nil {
                    Text(emptyMessage)
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
            .overlay {
                if viewModel.isLoading, viewModel.accounts.isEmpty {
                    ProgressView()
                }
            }
        }
        .background(LarpnetTheme.pageBackground)
        .task(id: viewModel.selectedFilter) { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private func row(for account: Account) -> some View {
        switch viewModel.selectedFilter {
        case .requests:
            VStack(alignment: .leading, spacing: 8) {
                accountButton(account)
                HStack {
                    Button("Accept") { viewModel.accept(account) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Accept & follow back") { viewModel.acceptAndFollowBack(account) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Decline", role: .destructive) { viewModel.decline(account) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        case .following:
            HStack {
                accountButton(account)
                Spacer(minLength: 8)
                Button("Unfollow") { viewModel.unfollow(account) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .followers, .notFollowingBack:
            HStack {
                accountButton(account)
                Spacer(minLength: 8)
                if let relationship = viewModel.relationshipsByAccountId[account.id], !relationship.following {
                    let label = relationship.requested ? "Requested" : "Follow back"
                    Button(label) { viewModel.follow(account) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(relationship.requested)
                }
            }
        }
    }

    private func accountButton(_ account: Account) -> some View {
        Button { onOpenProfile(account.id) } label: {
            AccountRow(account: account)
        }
        .buttonStyle(.plain)
    }

    private var emptyMessage: String {
        switch viewModel.selectedFilter {
        case .requests: "No pending follow requests."
        case .following: "You're not following anyone yet."
        case .followers: "No followers yet."
        case .notFollowingBack: "Everyone who follows you is followed back."
        }
    }
}

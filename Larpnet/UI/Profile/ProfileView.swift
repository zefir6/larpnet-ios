import SwiftUI

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    let onOpenThread: (Status) -> Void
    let onOpenProfile: (String) -> Void
    let onReply: (Status) -> Void
    let onEditProfile: () -> Void

    init(
        accountId: String?, appContainer: AppContainer,
        onOpenThread: @escaping (Status) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onReply: @escaping (Status) -> Void,
        onEditProfile: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ProfileViewModel(accountId: accountId, appContainer: appContainer))
        self.onOpenThread = onOpenThread
        self.onOpenProfile = onOpenProfile
        self.onReply = onReply
        self.onEditProfile = onEditProfile
    }

    var body: some View {
        ScrollView {
            if let account = viewModel.account {
                VStack(alignment: .leading, spacing: 8) {
                    RemoteImage(url: URL(string: account.avatar))
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    Text(account.displayName.isEmpty ? account.username : account.displayName)
                        .font(.title3.bold())
                    Text("@\(account.acct.isEmpty ? account.username : account.acct)")
                        .foregroundStyle(.secondary)
                    HTMLContentView(html: account.note)
                        .font(.subheadline)
                    HStack(spacing: 16) {
                        Text("\(account.statusesCount) posts")
                        Text("\(account.followersCount) followers")
                        Text("\(account.followingCount) following")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if viewModel.isOwnProfile {
                        Button("Edit Profile", action: onEditProfile)
                            .buttonStyle(.bordered)
                    } else if let relationship = viewModel.relationship {
                        Button(relationship.following ? "Unfollow" : "Follow") {
                            viewModel.toggleFollow()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .larpnetCard()
                .padding(.horizontal)
                .padding(.top, 8)
            }

            LazyVStack(spacing: 10) {
                ForEach(viewModel.statuses) { status in
                    StatusCard(
                        status: status,
                        onOpenThread: onOpenThread,
                        onOpenProfile: onOpenProfile,
                        onReply: onReply,
                        onToggleFavourite: { viewModel.toggleFavourite(id: $0) },
                        onToggleReblog: { viewModel.toggleReblog(id: $0) },
                        onToggleBookmark: { viewModel.toggleBookmark(id: $0) }
                    )
                    .padding(.horizontal, 6)
                    .contextMenu {
                        if viewModel.isOwnProfile {
                            Button("Delete", role: .destructive) { viewModel.delete(status) }
                        }
                    }
                    if status.id == viewModel.statuses.last?.id {
                        Color.clear.frame(height: 1)
                            .task { await viewModel.loadMore() }
                    }
                }
            }
            .padding(.top, 10)
        }
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.account == nil {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.account?.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

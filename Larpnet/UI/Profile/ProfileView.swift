import SwiftUI

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    let appContainer: AppContainer
    let onOpenThread: (Status) -> Void
    let onOpenProfile: (String) -> Void
    let onReply: (Status) -> Void
    let onEditProfile: () -> Void
    let onOpenHashtag: (String) -> Void

    init(
        accountId: String?, appContainer: AppContainer,
        onOpenThread: @escaping (Status) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onReply: @escaping (Status) -> Void,
        onEditProfile: @escaping () -> Void,
        onOpenHashtag: @escaping (String) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: ProfileViewModel(accountId: accountId, appContainer: appContainer))
        self.appContainer = appContainer
        self.onOpenThread = onOpenThread
        self.onOpenProfile = onOpenProfile
        self.onReply = onReply
        self.onEditProfile = onEditProfile
        self.onOpenHashtag = onOpenHashtag
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
                        let label = relationship.following ? "Unfollow" : (relationship.requested ? "Requested" : "Follow")
                        if relationship.following || relationship.requested {
                            Button(label) { viewModel.toggleFollow() }
                                .buttonStyle(.bordered)
                        } else {
                            Button(label) { viewModel.toggleFollow() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(12)
                .larpnetCard()
                .padding(.horizontal)
                .padding(.top, 8)
            }

            LazyVStack(spacing: 10) {
                ForEach(viewModel.visibleStatuses) { status in
                    StatusCard(
                        status: status,
                        onOpenThread: onOpenThread,
                        onOpenProfile: onOpenProfile,
                        onReply: onReply,
                        onToggleFavourite: { viewModel.toggleFavourite(id: $0) },
                        onToggleReblog: { viewModel.toggleReblog(id: $0) },
                        onToggleBookmark: { viewModel.toggleBookmark(id: $0) },
                        onOpenHashtag: onOpenHashtag,
                        currentAccountId: appContainer.currentAccountStore.accountId,
                        onDelete: viewModel.isOwnProfile ? { viewModel.delete($0) } : nil
                    )
                    .padding(.horizontal, 6)
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
        .postModerationHost(
            onHidePost: { id in
                appContainer.hiddenPostsStore.add(id)
            },
            onBlockPost: { id in
                appContainer.blockedPostsStore.add(id)
            },
            onBlockAccount: { accountId in
                viewModel.removeStatuses(byAccount: accountId)
                Task { try? await appContainer.friendicaAPI().block(id: accountId) }
            },
            onSubmitReport: { target, category, comment in
                Task {
                    try? await appContainer.friendicaAPI().report(
                        accountId: target.accountId, statusIds: target.statusIds, comment: comment, category: category
                    )
                }
            }
        )
    }
}

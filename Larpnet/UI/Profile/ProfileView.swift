import SwiftUI

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    // `RemoteImage` only re-fetches when its fetch id (url + `refreshToken`) actually changes --
    // `EditProfileViewModel.uploadAvatar` seeds `ImageLoader`'s cache with the freshly uploaded
    // bytes directly, but if the server happens to return the *same* literal avatar URL string
    // as before (unconfirmed either way), the URL alone wouldn't tell this screen's `RemoteImage`
    // instance to look again. Bumping this on every reappear-triggered reload below forces it to,
    // and since the cache is already correctly seeded by then, that's a guaranteed hit, not a
    // network round-trip.
    @State private var avatarRefreshToken = 0
    let appContainer: AppContainer
    let onOpenThread: (Status) -> Void
    let onOpenProfile: (String) -> Void
    let onReply: (Status) -> Void
    let onEditProfile: () -> Void
    let onOpenHashtag: (String) -> Void
    let onOpenAlbums: () -> Void

    init(
        accountId: String?, appContainer: AppContainer,
        onOpenThread: @escaping (Status) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onReply: @escaping (Status) -> Void,
        onEditProfile: @escaping () -> Void,
        onOpenHashtag: @escaping (String) -> Void = { _ in },
        onOpenAlbums: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: ProfileViewModel(accountId: accountId, appContainer: appContainer))
        self.appContainer = appContainer
        self.onOpenThread = onOpenThread
        self.onOpenProfile = onOpenProfile
        self.onReply = onReply
        self.onEditProfile = onEditProfile
        self.onOpenHashtag = onOpenHashtag
        self.onOpenAlbums = onOpenAlbums
    }

    var body: some View {
        ScrollView {
            if let account = viewModel.account {
                VStack(alignment: .leading, spacing: 8) {
                    RemoteImage(url: URL(string: account.avatar), refreshToken: viewModel.isOwnProfile ? avatarRefreshToken : 0)
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
                        HStack {
                            Button("Edit Profile", action: onEditProfile)
                                .buttonStyle(.bordered)
                            Button("Albums", action: onOpenAlbums)
                                .buttonStyle(.bordered)
                        }
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
        .toolbar {
            // Report/block a profile directly, not just via one of its posts -- an account
            // with no visible posts (a fresh account, or one whose posts are all hidden/
            // blocked already) would otherwise have no reachable moderation action at all.
            if let account = viewModel.account, !viewModel.isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileModerationMenu(account: account)
                }
            }
        }
        .task { await viewModel.load() }
        // `.task` only runs once, the first time this view is inserted -- it does not re-run
        // when the view merely reappears after a pushed child (e.g. Edit Profile) pops. Without
        // this, an avatar/display-name/bio change made on Edit Profile never becomes visible
        // here, since this screen's `viewModel` instance stays alive the whole time and is never
        // reloaded. `viewModel.account != nil` doubles as "already loaded once" so this doesn't
        // fire redundantly alongside `.task` on first appearance (account is still nil then).
        .onAppear {
            if viewModel.account != nil {
                avatarRefreshToken += 1
                Task { await viewModel.load() }
            }
        }
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

/// A separate `View` (not inline in `ProfileView.body`) so its `@Environment` read happens at
/// its own render point in the tree, nested under `ProfileView`'s `.postModerationHost` --
/// reading `moderationActions` directly in `ProfileView.body` itself would see the environment
/// `ProfileView` was handed by its *parent*, not the value `.postModerationHost` writes further
/// down within `ProfileView`'s own output. Mirrors `StatusCard`'s account-level actions
/// (`Block @handle` / `Report @handle…`) so the same "..." affordance is reachable from a
/// profile with zero visible posts, not just from one of its posts.
private struct ProfileModerationMenu: View {
    let account: Account
    @Environment(\.moderationActions) private var moderationActions

    var body: some View {
        if let actions = moderationActions {
            Menu {
                Button("Block @\(account.acct)", role: .destructive) {
                    actions.blockAccount(account.id)
                }
                Button("Report @\(account.acct)\u{2026}") {
                    actions.requestReportAccount(account.id, account.acct)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }
}

import SwiftUI

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    // `RemoteImage` only re-fetches when its `.task(id: url)` sees a genuinely different `URL`
    // value -- evicting the old entry from `ImageLoader`'s cache (done in
    // `EditProfileViewModel.uploadAvatar`) isn't enough on its own if Friendica happens to
    // return the *same* literal avatar URL string after an upload (unconfirmed either way).
    // Appending this token, bumped on every reappear-triggered reload below, guarantees a fresh
    // fetch regardless of server behavior.
    @State private var avatarCacheBustToken = 0
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
                    RemoteImage(url: displayedAvatarURL(for: account))
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
        .task { await viewModel.load() }
        // `.task` only runs once, the first time this view is inserted -- it does not re-run
        // when the view merely reappears after a pushed child (e.g. Edit Profile) pops. Without
        // this, an avatar/display-name/bio change made on Edit Profile never becomes visible
        // here, since this screen's `viewModel` instance stays alive the whole time and is never
        // reloaded. `viewModel.account != nil` doubles as "already loaded once" so this doesn't
        // fire redundantly alongside `.task` on first appearance (account is still nil then).
        .onAppear {
            if viewModel.account != nil {
                avatarCacheBustToken += 1
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

    /// Only own-profile reloads bump `avatarCacheBustToken`, and only own-profile pictures can
    /// have just been changed by this user -- another account's avatar is never cache-busted.
    private func displayedAvatarURL(for account: Account) -> URL? {
        guard viewModel.isOwnProfile, avatarCacheBustToken > 0,
              var components = URLComponents(string: account.avatar) else {
            return URL(string: account.avatar)
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "_cb", value: String(avatarCacheBustToken)))
        components.queryItems = items
        return components.url
    }
}

import SwiftUI

struct TimelineView: View {
    @State private var viewModel: TimelineViewModel
    let appContainer: AppContainer
    let onOpenThread: (Status) -> Void
    let onOpenProfile: (String) -> Void
    let onReply: (Status) -> Void
    let onOpenHashtag: (String) -> Void

    init(
        kind: TimelineKind, appContainer: AppContainer,
        onOpenThread: @escaping (Status) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onReply: @escaping (Status) -> Void,
        onOpenHashtag: @escaping (String) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: TimelineViewModel(kind: kind, appContainer: appContainer))
        self.appContainer = appContainer
        self.onOpenThread = onOpenThread
        self.onOpenProfile = onOpenProfile
        self.onReply = onReply
        self.onOpenHashtag = onOpenHashtag
    }

    var body: some View {
        ScrollView {
            if !viewModel.pendingNewPosts.isEmpty {
                NewPostsBanner(count: viewModel.pendingNewPosts.count) {
                    viewModel.mergePendingPosts()
                }
                .padding(.top, 4)
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
                        currentAccountId: appContainer.currentAccountStore.accountId
                    )
                    .padding(.horizontal, 6)
                    if status.id == viewModel.statuses.last?.id {
                        Color.clear.frame(height: 1)
                            .task { await viewModel.loadMore() }
                    }
                }
            }
            .padding(.top, 8)

            if viewModel.isLoadingMore {
                ProgressView().padding()
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .background(LarpnetTheme.pageBackground)
        .refreshable { await viewModel.refresh() }
        .overlay {
            if viewModel.isLoading, viewModel.statuses.isEmpty {
                ProgressView()
            }
        }
        .task { await viewModel.loadInitial() }
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
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

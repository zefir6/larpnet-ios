import SwiftUI

struct TimelineView: View {
    @State private var viewModel: TimelineViewModel
    let onOpenThread: (Status) -> Void
    let onOpenProfile: (String) -> Void
    let onReply: (Status) -> Void

    init(
        kind: TimelineKind, appContainer: AppContainer,
        onOpenThread: @escaping (Status) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onReply: @escaping (Status) -> Void
    ) {
        _viewModel = State(initialValue: TimelineViewModel(kind: kind, appContainer: appContainer))
        self.onOpenThread = onOpenThread
        self.onOpenProfile = onOpenProfile
        self.onReply = onReply
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
                ForEach(viewModel.statuses) { status in
                    StatusCard(
                        status: status,
                        onOpenThread: onOpenThread,
                        onOpenProfile: onOpenProfile,
                        onReply: onReply,
                        onToggleFavourite: { viewModel.toggleFavourite($0) },
                        onToggleReblog: { viewModel.toggleReblog($0) },
                        onToggleBookmark: { viewModel.toggleBookmark($0) }
                    )
                    .padding(.horizontal)
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
    }
}

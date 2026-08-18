import SwiftUI

struct ThreadView: View {
    @State private var viewModel: ThreadViewModel
    let onOpenThread: (Status) -> Void
    let onOpenProfile: (String) -> Void
    let onReply: (Status) -> Void

    init(
        statusId: String, appContainer: AppContainer,
        onOpenThread: @escaping (Status) -> Void,
        onOpenProfile: @escaping (String) -> Void,
        onReply: @escaping (Status) -> Void
    ) {
        _viewModel = State(initialValue: ThreadViewModel(statusId: statusId, appContainer: appContainer))
        self.onOpenThread = onOpenThread
        self.onOpenProfile = onOpenProfile
        self.onReply = onReply
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.ancestors) { status in
                    card(for: status, depth: 0)
                }
                if let focus = viewModel.focus {
                    card(for: focus, depth: 0)
                }
                ForEach(viewModel.descendantRows, id: \.status.id) { row in
                    card(for: row.status, depth: row.depth)
                }
            }
            .padding(.top, 8)
        }
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.focus == nil {
                ProgressView()
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func card(for status: Status, depth: Int) -> some View {
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
        .padding(.leading, CGFloat(depth) * 16)
    }
}

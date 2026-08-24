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

    /// A thread opened on a reply deep in a conversation (e.g. from a "mentioned you"
    /// notification) otherwise lands at the very top of the ancestor chain, leaving the actual
    /// post of interest below the fold -- looking like it "just opened the main post" instead of
    /// jumping to the one that was actually tapped. Scrolling to this id once the focus loads
    /// fixes that; for a thread with no ancestors it's a harmless no-op (already at the top).
    private static let focusScrollID = "thread-focus"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.ancestors) { status in
                        card(for: status, depth: 0)
                    }
                    if let focus = viewModel.focus {
                        card(for: focus, depth: 0)
                            .id(Self.focusScrollID)
                    }
                    ForEach(viewModel.descendantRows, id: \.status.id) { row in
                        card(for: row.status, depth: row.depth)
                    }
                }
                .padding(.top, 8)
            }
            .onChange(of: viewModel.focus?.id) { _, newValue in
                guard newValue != nil else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.focusScrollID, anchor: .top)
                }
            }
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
            onToggleFavourite: { viewModel.toggleFavourite(id: $0) },
            onToggleReblog: { viewModel.toggleReblog(id: $0) },
            onToggleBookmark: { viewModel.toggleBookmark(id: $0) }
        )
        .padding(.horizontal, 6)
        .padding(.leading, CGFloat(depth) * 16)
    }
}

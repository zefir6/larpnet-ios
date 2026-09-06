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
    /// Keyed on `focus?.id`, not on `isLoading` or `focus` itself -- an id doesn't change when a
    /// favourite/reblog/bookmark toggle replaces the `focus` object with updated counts, so this
    /// already survives those toggles without re-scrolling, no `isLoading`-keyed workaround
    /// needed (Android's `LaunchedEffect(state.isLoading)` solves the same problem differently
    /// because Compose's recomposition semantics differ).
    private static let focusScrollID = "thread-focus"

    /// Indentation stops growing past this depth so a very deep sub-thread doesn't squeeze
    /// cards down to nothing -- matches Android's `MAX_INDENT_DEPTH`.
    private static let maxIndentDepth = 6

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.ancestors) { status in
                        card(for: status, flat: true, isFocus: false)
                        divider()
                    }
                    if let focus = viewModel.focus {
                        card(for: focus, flat: true, isFocus: true)
                            .background(LarpnetTheme.highlight)
                            .id(Self.focusScrollID)
                        if !viewModel.descendants.isEmpty { divider() }
                    }
                    ForEach(Array(viewModel.descendants.enumerated()), id: \.element.status.id) { index, item in
                        descendantRow(item)
                        if index < viewModel.descendants.count - 1 { divider() }
                    }
                }
                .larpnetCard()
                .padding(.horizontal, 6)
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

    private func divider() -> some View {
        Divider().overlay(LarpnetTheme.pageBackground)
    }

    @ViewBuilder
    private func descendantRow(_ item: ThreadRenderItem) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if item.hasChildren {
                Button {
                    viewModel.toggleCollapsed(id: item.status.id)
                } label: {
                    Image(systemName: item.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            VStack(alignment: .leading, spacing: 4) {
                card(for: item.status, flat: true, isFocus: false)
                if item.isCollapsed, item.hiddenDescendantCount > 0 {
                    Button {
                        viewModel.toggleCollapsed(id: item.status.id)
                    } label: {
                        Text("\(item.hiddenDescendantCount) repl\(item.hiddenDescendantCount == 1 ? "y" : "ies")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                            .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, CGFloat(min(item.depth, Self.maxIndentDepth)) * 16)
    }

    @ViewBuilder
    private func card(for status: Status, flat: Bool, isFocus: Bool) -> some View {
        StatusCard(
            status: status,
            flat: flat,
            onOpenThread: isFocus ? { _ in } : onOpenThread,
            onOpenProfile: onOpenProfile,
            onReply: onReply,
            onToggleFavourite: { viewModel.toggleFavourite(id: $0) },
            onToggleReblog: { viewModel.toggleReblog(id: $0) },
            onToggleBookmark: { viewModel.toggleBookmark(id: $0) }
        )
    }
}

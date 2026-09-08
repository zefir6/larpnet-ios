import SwiftUI

struct MediaGridView: View {
    @State private var viewModel: MediaGridViewModel
    let onOpenThread: (String) -> Void

    private static let columnCount = 3
    private static let spacing: CGFloat = 4

    init(appContainer: AppContainer, onOpenThread: @escaping (String) -> Void) {
        _viewModel = State(initialValue: MediaGridViewModel(appContainer: appContainer))
        self.onOpenThread = onOpenThread
    }

    var body: some View {
        // A fixed column count with an explicit, hard-computed pixel `cellSize` -- not
        // `GridItem(.adaptive(minimum:))` + `.aspectRatio(1, contentMode: .fill)` on the cell
        // content, which turned out not to reliably constrain each cell to the grid's proposed
        // column width in practice (confirmed live: cells rendered at wildly different sizes,
        // some nearly full-width, overlapping each other rather than forming rows). Explicit
        // `.frame(width:height:)` on every cell leaves no ambiguity for the layout system to get
        // wrong.
        GeometryReader { geometry in
            let cellSize = (geometry.size.width - Self.spacing * CGFloat(Self.columnCount + 1)) / CGFloat(Self.columnCount)
            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: Self.spacing), count: Self.columnCount)
            ScrollView {
                LazyVGrid(columns: columns, spacing: Self.spacing) {
                    ForEach(viewModel.items) { item in
                        Button {
                            onOpenThread(item.statusId)
                        } label: {
                            RemoteImage(url: URL(string: item.media.previewUrl ?? item.media.url))
                                .frame(width: cellSize, height: cellSize)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        // `.task(id:)`, not `.onAppear` -- runs exactly once when this cell is
                        // first lazily instantiated by `LazyVGrid` (i.e. as it approaches the
                        // viewport), not every time it merely scrolls in/out during fast or
                        // bouncy scrolling the way `.onAppear` would re-fire. Attached to the
                        // cell itself (rather than a separate sentinel placed after the grid)
                        // because a sentinel outside `LazyVGrid` sits in the plain, non-lazy
                        // `ScrollView` around it and would run immediately on screen load
                        // instead of waiting for scroll -- being *inside* the lazy container is
                        // what makes the "wait until near the bottom" behavior work at all.
                        // Matches the intent of the `Color.clear.task { }` sentinel
                        // `TimelineView`/`ProfileView` use inside their own `LazyVStack`s,
                        // adapted for a 2D grid where an extra sentinel cell would disrupt
                        // column layout.
                        .task(id: item.id) {
                            if item.id == viewModel.items.last?.id {
                                await viewModel.loadMore()
                            }
                        }
                    }
                }
                .padding(Self.spacing)

                if viewModel.items.isEmpty, !viewModel.isLoading {
                    Text("No photos or videos in your posts yet.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
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
            .overlay {
                if viewModel.isLoading, viewModel.items.isEmpty {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadInitial() }
    }
}

import SwiftUI

struct MediaGridView: View {
    @State private var viewModel: MediaGridViewModel
    let onOpenThread: (String) -> Void

    private static let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    init(appContainer: AppContainer, onOpenThread: @escaping (String) -> Void) {
        _viewModel = State(initialValue: MediaGridViewModel(appContainer: appContainer))
        self.onOpenThread = onOpenThread
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(viewModel.items) { item in
                    Button {
                        onOpenThread(item.statusId)
                    } label: {
                        RemoteImage(url: URL(string: item.media.previewUrl ?? item.media.url))
                            .aspectRatio(1, contentMode: .fill)
                            .frame(minHeight: 100)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                    // `.task(id:)`, not `.onAppear` -- runs exactly once when this cell is
                    // first lazily instantiated by `LazyVGrid` (i.e. as it approaches the
                    // viewport), not every time it merely scrolls in/out during fast or bouncy
                    // scrolling the way `.onAppear` would re-fire. Attached to the cell itself
                    // (rather than a separate sentinel placed after the grid) because a sentinel
                    // outside `LazyVGrid` sits in the plain, non-lazy `ScrollView` around it and
                    // would run immediately on screen load instead of waiting for scroll --
                    // being *inside* the lazy container is what makes the "wait until near the
                    // bottom" behavior work at all. Matches the intent of the
                    // `Color.clear.task { }` sentinel `TimelineView`/`ProfileView` use inside
                    // their own `LazyVStack`s, adapted for a 2D grid where an extra sentinel
                    // cell would disrupt column layout.
                    .task(id: item.id) {
                        if item.id == viewModel.items.last?.id {
                            await viewModel.loadMore()
                        }
                    }
                }
            }
            .padding(4)

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
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadInitial() }
    }
}

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
                            .clipped()
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == viewModel.items.last?.id {
                            Task { await viewModel.loadMore() }
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

import PhotosUI
import SwiftUI

struct AlbumDetailView: View {
    @State private var viewModel: AlbumDetailViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var deleteCandidate: FriendicaPhoto?

    /// Multi-select, capped -- "upload photos" (plural) is the point, but an unbounded pick
    /// risks a very long sequential upload run; 20 is a generous, arbitrary-but-reasonable limit
    /// for one batch.
    private static let maxSelectionCount = 20
    private static let columnCount = 3
    private static let spacing: CGFloat = 4

    init(albumName: String, appContainer: AppContainer) {
        _viewModel = State(initialValue: AlbumDetailViewModel(albumName: albumName, appContainer: appContainer))
    }

    var body: some View {
        // A fixed column count with an explicit, hard-computed pixel `cellSize` -- not
        // `GridItem(.adaptive(minimum:))` + `.aspectRatio(1, contentMode: .fill)` on the cell
        // content, which turned out not to reliably constrain each cell to the grid's proposed
        // column width in practice (confirmed live against `MediaGridView`'s identical pattern:
        // cells rendered at wildly different sizes, some nearly full-width, overlapping each
        // other rather than forming rows). Explicit `.frame(width:height:)` on every cell leaves
        // no ambiguity for the layout system to get wrong.
        GeometryReader { geometry in
            let cellSize = (geometry.size.width - Self.spacing * CGFloat(Self.columnCount + 1)) / CGFloat(Self.columnCount)
            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: Self.spacing), count: Self.columnCount)
            ScrollView {
                LazyVGrid(columns: columns, spacing: Self.spacing) {
                    ForEach(viewModel.photos) { photo in
                        RemoteImage(url: URL(string: photo.thumb))
                            .frame(width: cellSize, height: cellSize)
                            .clipped()
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Delete", role: .destructive) { deleteCandidate = photo }
                            }
                    }
                }
                .padding(Self.spacing)

                if viewModel.photos.isEmpty, !viewModel.isLoading, !viewModel.isUploading {
                    Text("No photos in this album yet.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
                if viewModel.isUploading {
                    ProgressView("Uploading\u{2026}").padding()
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
                if viewModel.isLoading, viewModel.photos.isEmpty {
                    ProgressView()
                }
            }
        }
        .navigationTitle(viewModel.albumName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(
                    selection: $pickerItems, maxSelectionCount: Self.maxSelectionCount, matching: .images
                ) {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.isUploading)
            }
        }
        .onChange(of: pickerItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            let items = newValue
            pickerItems = []
            Task { await viewModel.upload(items) }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            presenting: deleteCandidate
        ) { photo in
            Button("Delete", role: .destructive) {
                viewModel.delete(photo)
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        .task { await viewModel.load() }
    }
}

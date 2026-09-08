import SwiftUI

struct AlbumsView: View {
    @State private var viewModel: AlbumsViewModel
    @State private var isPresentingNewAlbumAlert = false
    @State private var newAlbumName = ""
    let onOpenAlbum: (String) -> Void

    init(appContainer: AppContainer, onOpenAlbum: @escaping (String) -> Void) {
        _viewModel = State(initialValue: AlbumsViewModel(appContainer: appContainer))
        self.onOpenAlbum = onOpenAlbum
    }

    var body: some View {
        List {
            ForEach(viewModel.albums) { album in
                Button {
                    onOpenAlbum(album.name)
                } label: {
                    HStack {
                        Text(album.name)
                        Spacer()
                        Text("\(album.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            if viewModel.albums.isEmpty, !viewModel.isLoading, viewModel.errorMessage == nil {
                Text("No albums yet. Create one to start uploading photos.")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.albums.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newAlbumName = ""
                    isPresentingNewAlbumAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Album", isPresented: $isPresentingNewAlbumAlert) {
            TextField("Album name", text: $newAlbumName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                viewModel.addLocalPlaceholder(name: name)
                onOpenAlbum(name)
            }
        } message: {
            Text("You can start uploading photos to it right away.")
        }
        .task { await viewModel.load() }
    }
}

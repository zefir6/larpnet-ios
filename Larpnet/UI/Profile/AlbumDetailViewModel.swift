import Foundation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class AlbumDetailViewModel {
    let albumName: String
    private(set) var photos: [FriendicaPhoto] = []
    private(set) var isLoading = false
    private(set) var isUploading = false
    var errorMessage: String?

    private let appContainer: AppContainer

    init(albumName: String, appContainer: AppContainer) {
        self.albumName = albumName
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            photos = try await appContainer.friendicaAPI().photos(inAlbum: albumName)
            errorMessage = nil
        } catch {
            // A brand-new album (created locally in `AlbumsViewModel.addLocalPlaceholder`, no
            // photo uploaded yet) has no server-side existence yet -- `photoalbum?album=` on a
            // name with zero photos is expected to come back empty or 404 depending on server
            // version, neither of which is a real error worth surfacing here.
            photos = []
        }
    }

    /// Uploads sequentially, not concurrently -- bounded by construction (one in flight at a
    /// time), simpler than `LocalPostListViewModel`'s batched `TaskGroup` and fine for the
    /// handful of photos a person picks in one go from `PhotosPicker`.
    func upload(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }
        let api = try? appContainer.friendicaAPI()
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.85) else { continue }
            do {
                try await api?.uploadPhoto(data: jpeg, mimeType: "image/jpeg", filename: "\(UUID()).jpg", album: albumName)
            } catch {
                errorMessage = String(describing: error)
            }
        }
        await load()
    }

    func delete(_ photo: FriendicaPhoto) {
        photos.removeAll { $0.id == photo.id }
        Task { try? await appContainer.friendicaAPI().deletePhoto(id: photo.id) }
    }
}

import Foundation

@MainActor
@Observable
final class AlbumsViewModel {
    private(set) var albums: [FriendicaPhotoAlbum] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let appContainer: AppContainer

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            albums = try await appContainer.friendicaAPI().photoAlbums()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// A new album has no dedicated creation endpoint -- it comes into existence server-side the
    /// moment a photo is uploaded with a name that doesn't exist yet, so this just adds a
    /// zero-count placeholder locally so the new album is immediately visible and tappable
    /// before any photo has actually landed in it.
    func addLocalPlaceholder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !albums.contains(where: { $0.name == trimmed }) else { return }
        albums.insert(FriendicaPhotoAlbum(name: trimmed, count: 0), at: 0)
    }
}

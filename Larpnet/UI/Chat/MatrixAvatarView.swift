import SwiftUI

/// Process-lifetime in-memory cache of decoded avatar thumbnails, keyed by `mxc://` URL -- keeps
/// `MatrixAvatarView` from re-fetching (and re-decoding) the same image every time a message
/// bubble/room row scrolls back into view. Not persisted to disk: avatars are small and cheap
/// enough to refetch on a cold launch, and this avoids owning a cache-invalidation story for
/// someone changing their avatar.
@MainActor
private final class MatrixAvatarCache {
    static let shared = MatrixAvatarCache()
    private var images: [String: UIImage] = [:]

    func image(for url: String) -> UIImage? { images[url] }
    func store(_ image: UIImage, for url: String) { images[url] = image }
}

/// A chat avatar that shows the real Matrix profile photo when one is set, falling back to
/// `InitialsAvatar` while it loads or when there isn't one -- used for both per-message sender
/// avatars (`ChatThreadView`) and room-list rows (`ChatView`), so a real photo replaces the
/// initials placeholder wherever the SDK has one instead of the app inventing its own avatar
/// pipeline per call site.
struct MatrixAvatarView: View {
    let avatarUrl: String?
    let name: String
    var size: CGFloat = 44
    let appContainer: AppContainer

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                InitialsAvatar(name: name, size: size)
            }
        }
        .task(id: avatarUrl) {
            image = nil
            await load()
        }
    }

    private func load() async {
        guard let avatarUrl else { return }
        if let cached = MatrixAvatarCache.shared.image(for: avatarUrl) {
            image = cached
            return
        }
        guard let data = try? await appContainer.matrixClientStore.avatarThumbnail(mxcUrl: avatarUrl),
              let loaded = UIImage(data: data) else { return }
        MatrixAvatarCache.shared.store(loaded, for: avatarUrl)
        image = loaded
    }
}

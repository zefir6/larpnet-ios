import Foundation
import PhotosUI
import SwiftUI

/// Direct port of Android's `ui/compose/ComposeViewModel.kt`: new post or reply, spoiler
/// text (content warning), visibility, sensitive flag, media attach/upload. Only
/// `public`/`unlisted`/`private` are offered -- `direct` visibility posts aren't surfaced back
/// by the Mastodon API layer on this server (see `Status`'s doc comment), so DMs go through the
/// separate Conversations/Messages flow instead, matching Android.
@MainActor
@Observable
final class ComposeViewModel {
    var text: String = ""
    var spoilerText: String = ""
    var isSpoilerEnabled: Bool = false
    var visibility: String = "public"
    var sensitive: Bool = false
    private(set) var pendingMedia: [PendingMedia] = []
    private(set) var isPublishing = false
    var errorMessage: String?

    let replyToId: String?
    private let appContainer: AppContainer

    struct PendingMedia: Identifiable {
        let id: UUID
        var image: UIImage
        var uploadedId: String?
        var isUploading: Bool

        init(id: UUID = UUID(), image: UIImage, uploadedId: String? = nil, isUploading: Bool = false) {
            self.id = id
            self.image = image
            self.uploadedId = uploadedId
            self.isUploading = isUploading
        }
    }

    init(replyToId: String?, appContainer: AppContainer) {
        self.replyToId = replyToId
        self.appContainer = appContainer
    }

    var canPublish: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPublishing
            && !pendingMedia.contains { $0.isUploading }
    }

    func addMedia(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            let pendingId = UUID()
            pendingMedia.append(PendingMedia(id: pendingId, image: image, isUploading: true))
            guard let jpegData = image.jpegData(compressionQuality: 0.85) else { return }
            do {
                let api = try appContainer.friendicaAPI()
                let attachment = try await api.uploadMedia(
                    data: jpegData, mimeType: "image/jpeg", filename: "\(pendingId).jpg"
                )
                setUploaded(pendingId, mediaId: attachment.id)
            } catch {
                errorMessage = String(describing: error)
                removeMedia(pendingId)
            }
        }
    }

    private func setUploaded(_ id: UUID, mediaId: String) {
        guard let index = pendingMedia.firstIndex(where: { $0.id == id }) else { return }
        pendingMedia[index].uploadedId = mediaId
        pendingMedia[index].isUploading = false
    }

    func removeMedia(_ id: UUID) {
        pendingMedia.removeAll { $0.id == id }
    }

    func publish() async -> Bool {
        guard canPublish else { return false }
        isPublishing = true
        defer { isPublishing = false }
        do {
            let api = try appContainer.friendicaAPI()
            _ = try await api.postStatus(
                status: text,
                inReplyToId: replyToId,
                visibility: visibility,
                spoilerText: isSpoilerEnabled ? spoilerText : nil,
                sensitive: sensitive,
                mediaIds: pendingMedia.compactMap(\.uploadedId)
            )
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }
}

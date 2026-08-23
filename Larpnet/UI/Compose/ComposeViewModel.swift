import Foundation
import PhotosUI
import SwiftUI

/// Direct port of Android's `ui/compose/ComposeViewModel.kt`: new post or reply, spoiler
/// text (content warning), visibility, sensitive flag, media attach/upload. Only
/// `public`/`unlisted`/`private` are offered -- `direct` visibility posts aren't surfaced back
/// by the Mastodon API layer on this server (see `Status`'s doc comment), so DMs go through the
/// separate Conversations/Messages flow instead, matching Android.
///
/// The custom-audience feature (`isCustomAudience`/`circles`/`selectedCircleIds`/etc.) has no
/// Android counterpart -- it's net-new, built on a Friendica-only API `postStatus`'s standard
/// endpoint can't express (see `FriendicaAPIClient.postStatusWithACL`'s doc comment for why a
/// separate legacy endpoint is needed, and what it can't do: no `sensitive` flag, no media).
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

    /// When true, `visibility`/`sensitive`/media are ignored and the post goes to exactly
    /// `selectedCircleIds` + `selectedAccountIds` instead (see `publish()`).
    var isCustomAudience = false
    private(set) var circles: [FriendicaCircle] = []
    private(set) var followers: [Account] = []
    private(set) var isLoadingAudience = false
    var selectedCircleIds: Set<String> = []
    var selectedAccountIds: Set<String> = []
    private var followersMaxId: String?
    private var followersReachedEnd = false
    private var selfAccountId: String?

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
            && (!isCustomAudience || !(selectedCircleIds.isEmpty && selectedAccountIds.isEmpty))
    }

    /// Fetches circles + the first page of followers for the audience picker, once, the first
    /// time it's opened -- not on every compose launch, since most posts never use it.
    func loadAudienceIfNeeded() async {
        guard circles.isEmpty, followers.isEmpty, !isLoadingAudience else { return }
        isLoadingAudience = true
        defer { isLoadingAudience = false }
        do {
            let api = try appContainer.friendicaAPI()
            async let circlesTask = api.circles()
            let me = try await api.verifyCredentials()
            selfAccountId = me.id
            let page = try await api.followers(id: me.id)
            circles = try await circlesTask
            followers = page.items
            followersMaxId = page.nextMaxId
            followersReachedEnd = page.nextMaxId == nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadMoreFollowers() async {
        guard !followersReachedEnd, let maxId = followersMaxId, let selfAccountId else { return }
        do {
            let api = try appContainer.friendicaAPI()
            let page = try await api.followers(id: selfAccountId, maxId: maxId)
            followers.append(contentsOf: page.items)
            followersMaxId = page.nextMaxId
            followersReachedEnd = page.nextMaxId == nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleCircle(_ id: String) {
        if selectedCircleIds.contains(id) { selectedCircleIds.remove(id) } else { selectedCircleIds.insert(id) }
    }

    func toggleAccount(_ id: String) {
        if selectedAccountIds.contains(id) { selectedAccountIds.remove(id) } else { selectedAccountIds.insert(id) }
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
            if isCustomAudience {
                _ = try await api.postStatusWithACL(
                    status: text,
                    title: isSpoilerEnabled ? spoilerText : nil,
                    inReplyToId: replyToId,
                    contactIds: Array(selectedAccountIds),
                    circleIds: Array(selectedCircleIds)
                )
            } else {
                _ = try await api.postStatus(
                    status: text,
                    inReplyToId: replyToId,
                    visibility: visibility,
                    spoilerText: isSpoilerEnabled ? spoilerText : nil,
                    sensitive: sensitive,
                    mediaIds: pendingMedia.compactMap(\.uploadedId)
                )
            }
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }
}

import Foundation
import PhotosUI
import SwiftUI

/// Direct port of Android's `ui/compose/ComposeViewModel.kt`: new post or reply, spoiler
/// text (content warning), visibility, sensitive flag, media attach/upload.
/// `public`/`unlisted`/`private`/`local` are offered -- `direct` visibility posts aren't
/// surfaced back by the Mastodon API layer on this server (see `Status`'s doc comment), so DMs
/// go through the separate Conversations/Messages flow instead, matching Android. `local` is
/// Friendica-larpnet's own server-only visibility level: a real value the standard
/// `postStatus` call understands directly (`Item::SERVER_ONLY` server-side, never federated to
/// other instances), not a compose-only sentinel like the custom-audience feature below.
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
    static let predefinedTags = ["larp", "random"]
    var selectedTags: Set<String> = []
    private(set) var customTags: [String] = []
    var customTagInput: String = ""
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

    /// Predefined + this session's recent tags (from `AppContainer.recentTagsStore`), deduped
    /// case-insensitively, predefined ones first -- same priority as Android's `TagsSection.kt`.
    var toggleableTags: [String] {
        let recent = appContainer.recentTagsStore.recentTags.filter { recent in
            !Self.predefinedTags.contains { $0.caseInsensitiveCompare(recent) == .orderedSame }
        }
        return Self.predefinedTags + recent
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
    }

    /// Normalizes free-typed input (trim, strip one leading `#`, lowercase, reject anything
    /// still containing whitespace after that) and either toggles an existing predefined/recent
    /// chip if it matches, or adds a new custom chip -- mirrors Android's `addCustomTag()`.
    func addCustomTag() {
        var normalized = customTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") { normalized.removeFirst() }
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        customTagInput = ""
        guard !normalized.isEmpty, !normalized.contains(where: \.isWhitespace) else { return }

        if let existing = toggleableTags.first(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            selectedTags.insert(existing)
            return
        }
        if let existing = customTags.first(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            selectedTags.insert(existing)
            return
        }
        customTags.append(normalized)
        selectedTags.insert(normalized)
    }

    func removeCustomTag(_ tag: String) {
        customTags.removeAll { $0 == tag }
        selectedTags.remove(tag)
    }

    private var tagsToPublish: [String] {
        (toggleableTags + customTags).filter { selectedTags.contains($0) }
    }

    /// Folds selected tags into the outgoing body as `#tag` tokens -- there's no dedicated tags
    /// API field, the server derives hashtags from the post text itself (see Android's
    /// `ComposeViewModel.buildStatusText`).
    private var textToPublish: String {
        let tags = tagsToPublish
        guard !tags.isEmpty else { return text }
        let tagLine = tags.map { "#\($0)" }.joined(separator: " ")
        return text.isEmpty ? tagLine : "\(text)\n\n\(tagLine)"
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
            let body = textToPublish
            if isCustomAudience {
                _ = try await api.postStatusWithACL(
                    status: body,
                    title: isSpoilerEnabled ? spoilerText : nil,
                    inReplyToId: replyToId,
                    contactIds: Array(selectedAccountIds),
                    circleIds: Array(selectedCircleIds)
                )
            } else {
                _ = try await api.postStatus(
                    status: body,
                    inReplyToId: replyToId,
                    visibility: visibility,
                    spoilerText: isSpoilerEnabled ? spoilerText : nil,
                    sensitive: sensitive,
                    mediaIds: pendingMedia.compactMap(\.uploadedId)
                )
            }
            for tag in tagsToPublish { appContainer.recentTagsStore.recordUsed(tag) }
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }
}

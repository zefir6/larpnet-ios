import Foundation
import PhotosUI
import SwiftSoup
import SwiftUI

/// Direct port of Android's `EditProfileViewModel` (inline in `EditProfileScreen.kt`):
/// display name + bio editor, locked/discoverable/bot switches, PATCHes via
/// `update_credentials`. The bio is converted from HTML to plain text before editing (Friendica
/// stores `note` as HTML), matching Android's use of Jsoup for the same conversion.
///
/// Avatar upload is a separate call (`uploadAvatarImage`, not `updateCredentials`) -- see its
/// doc comment in `FriendicaAPIClient` for why the two can't share one request.
@MainActor
@Observable
final class EditProfileViewModel {
    var displayName: String = ""
    var note: String = ""
    var locked: Bool = false
    var discoverable: Bool = false
    var bot: Bool = false
    private(set) var avatarURL: String = ""
    /// Bumped on every successful upload -- fed to `RemoteImage`'s `refreshToken` so this
    /// screen's own small preview re-fetches even if `avatarURL`'s string happens to be
    /// unchanged (its `.task(id:)` otherwise has no way to know a cache mutation happened
    /// elsewhere).
    private(set) var avatarVersion = 0
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// Avatar upload happens immediately on cropping, separate from `save()`'s text-field PATCH --
    /// same "commits right away" UX as changing a photo in most apps, rather than bundling it
    /// into the deferred "Save" action.
    private(set) var isUploadingAvatar = false
    /// Non-nil drives `AvatarCropView`'s sheet presentation -- set once a picked photo has been
    /// successfully decoded, cleared on cancel or once cropping hands back a result to upload.
    private(set) var imageToCrop: UIImage?
    var errorMessage: String?

    private let appContainer: AppContainer

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let account = try await appContainer.friendicaAPI().verifyCredentials()
            displayName = account.displayName
            note = (try? SwiftSoup.parse(account.note).text()) ?? account.note
            locked = account.locked
            discoverable = account.discoverable
            avatarURL = account.avatar
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Loads and decodes the picked photo, then stages it for `AvatarCropView` -- the actual
    /// upload only happens once the user confirms a crop, via `uploadAvatar(_:)` below.
    func stageAvatarForCropping(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't read that photo."
                return
            }
            imageToCrop = image
        }
    }

    func cancelCropping() {
        imageToCrop = nil
    }

    func uploadAvatar(_ croppedImage: UIImage) {
        imageToCrop = nil
        Task {
            isUploadingAvatar = true
            errorMessage = nil
            defer { isUploadingAvatar = false }
            guard let jpeg = croppedImage.jpegData(compressionQuality: 0.85) else {
                errorMessage = "Couldn't process that photo."
                return
            }
            do {
                let account = try await appContainer.friendicaAPI().uploadAvatarImage(
                    data: jpeg, mimeType: "image/jpeg", filename: "avatar.jpg"
                )
                // Seed the cache with the exact bytes just uploaded, keyed under whatever URL
                // the server handed back -- stronger than evicting and hoping a re-fetch picks
                // up fresh bytes, since it sidesteps any question of whether Cloudflare (fronting
                // larpnet.pl) would still serve a stale cached response for that URL path even
                // right after an eviction here. Every screen showing this account's avatar
                // (`ProfileView` via its own reload) ends up requesting this exact URL, so this
                // is a guaranteed hit, not a network round-trip, once they do.
                if let newURL = URL(string: account.avatar) {
                    appContainer.imageLoader.store(croppedImage, for: newURL)
                }
                avatarURL = account.avatar
                avatarVersion += 1
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    func save() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await appContainer.friendicaAPI().updateCredentials(
                displayName: displayName, note: note, locked: locked, discoverable: discoverable, bot: bot
            )
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }
}

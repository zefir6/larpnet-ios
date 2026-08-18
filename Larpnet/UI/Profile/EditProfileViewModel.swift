import Foundation
import SwiftSoup

/// Direct port of Android's `EditProfileViewModel` (inline in `EditProfileScreen.kt`):
/// display name + bio editor, locked/discoverable/bot switches, PATCHes via
/// `update_credentials`. The bio is converted from HTML to plain text before editing (Friendica
/// stores `note` as HTML), matching Android's use of Jsoup for the same conversion.
@MainActor
@Observable
final class EditProfileViewModel {
    var displayName: String = ""
    var note: String = ""
    var locked: Bool = false
    var discoverable: Bool = false
    var bot: Bool = false
    private(set) var isLoading = false
    private(set) var isSaving = false
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
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
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

import Foundation
import UserNotifications

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var account: Account?
    var pushEnabled: Bool {
        didSet { appContainer.tokenStore.pushEnabled = pushEnabled }
    }
    var locked = false
    var discoverable = false
    var bot = false
    var errorMessage: String?

    private let appContainer: AppContainer

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
        self.pushEnabled = appContainer.tokenStore.pushEnabled
    }

    func load() async {
        do {
            let resolved = try await appContainer.friendicaAPI().verifyCredentials()
            account = resolved
            locked = resolved.locked
            discoverable = resolved.discoverable
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func togglePush(_ enabled: Bool) {
        pushEnabled = enabled
        if enabled {
            Task {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if granted {
                    BackgroundRefresh.schedule()
                } else {
                    pushEnabled = false
                }
            }
        } else {
            BackgroundRefresh.cancel()
        }
    }

    func savePrivacy() {
        Task {
            do {
                let updated = try await appContainer.friendicaAPI().updateCredentials(
                    displayName: nil, note: nil, locked: locked, discoverable: discoverable, bot: bot
                )
                account = updated
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    var webSettingsURL: URL? {
        guard let base = appContainer.tokenStore.instanceBaseURL else { return nil }
        return URL(string: "settings/profile", relativeTo: URL(string: base))
    }
}

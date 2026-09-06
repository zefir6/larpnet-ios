import Foundation

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
                await BackgroundRefresh.requestAuthorizationIfNeededAndSchedule(tokenStore: appContainer.tokenStore)
                // `requestAuthorizationIfNeededAndSchedule` may flip `tokenStore.pushEnabled`
                // back to false (denied/not granted) -- mirror that into this view's own state
                // so the toggle visually reflects it instead of staying stuck "on".
                pushEnabled = appContainer.tokenStore.pushEnabled
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

    /// Port of Android's Settings "Bezpieczeństwo" section (commit 773185d), added for Play
    /// Store's Child Safety Standards / in-app abuse-reporting requirement -- Apple's App Store
    /// has an analogous UGC-app requirement, so this carries over as-is. `URLComponents`, not a
    /// raw `URL(string: "mailto:...?subject=...")`: a literal space in the subject makes that
    /// initializer return `nil`, and both URLs here are compile-time constants, never
    /// legitimately absent (unlike `webSettingsURL` above), so a non-optional force-unwrap is
    /// appropriate.
    var reportAbuseURL: URL {
        var components = URLComponents(string: "mailto:admin@larpnet.pl")!
        components.queryItems = [URLQueryItem(name: "subject", value: "Larpnet abuse report")]
        return components.url!
    }

    var childSafetyStandardsURL: URL {
        URL(string: "https://larpnet.pl/child-safety-standards.html")!
    }
}

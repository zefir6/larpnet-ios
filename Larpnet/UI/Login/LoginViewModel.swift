import Foundation

/// Direct port of Android's `ui/login/LoginViewModel.kt`'s state machine, minus the
/// `ON_RESUME`-based "recover from backing out of the browser" workaround Android needed --
/// `ASWebAuthenticationSession`'s completion handler fires on cancel too (as
/// `OAuthFlow.OAuthError.cancelled`), so there's no equivalent "stuck on Opening browser..."
/// failure mode to guard against here.
enum LoginUIState: Equatable {
    case idle
    case awaitingBrowser
    case exchangingToken
    case error(String)
    case loggedIn
}

@MainActor
@Observable
final class LoginViewModel {
    private(set) var uiState: LoginUIState = .idle

    private let oAuthFlow: OAuthFlow
    private let tokenStore: TokenStore

    init(oAuthFlow: OAuthFlow, tokenStore: TokenStore) {
        self.oAuthFlow = oAuthFlow
        self.tokenStore = tokenStore
    }

    func login() {
        guard uiState != .awaitingBrowser, uiState != .exchangingToken else { return }
        // Read fresh at the moment of the tap, not cached at init -- the only way to change
        // this is the iOS Settings app's "Larpnet" page (see `Settings.bundle/Root.plist`),
        // which the user could easily have visited *while this screen sat backgrounded*, so
        // caching it earlier risks logging into a stale instance.
        let instance = tokenStore.preferredInstance
        uiState = .awaitingBrowser
        Task {
            do {
                try await oAuthFlow.login(instanceInput: instance)
                tokenStore.preferredInstance = instance.trimmingCharacters(in: .whitespacesAndNewlines)
                uiState = .exchangingToken
                uiState = .loggedIn
            } catch OAuthFlow.OAuthError.cancelled {
                uiState = .idle
            } catch {
                uiState = .error(String(describing: error))
            }
        }
    }
}

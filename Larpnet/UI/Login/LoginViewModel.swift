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
    var instanceInput: String
    private(set) var uiState: LoginUIState = .idle

    private let oAuthFlow: OAuthFlow
    private let tokenStore: TokenStore

    init(oAuthFlow: OAuthFlow, tokenStore: TokenStore) {
        self.oAuthFlow = oAuthFlow
        self.tokenStore = tokenStore
        // Prefills with whatever was last used successfully (Settings' "Server" control, or
        // simply the last instance logged into) -- falls back to the baked-in default
        // (`TokenStore.defaultInstance`, "larpnet.pl") until either of those has ever run.
        self.instanceInput = tokenStore.preferredInstance
    }

    func login() {
        guard uiState != .awaitingBrowser, uiState != .exchangingToken else { return }
        uiState = .awaitingBrowser
        Task {
            do {
                try await oAuthFlow.login(instanceInput: instanceInput)
                tokenStore.preferredInstance = instanceInput.trimmingCharacters(in: .whitespacesAndNewlines)
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

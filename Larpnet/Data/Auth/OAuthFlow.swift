import AuthenticationServices
import Foundation

/// Hand-rolled OAuth2 authorization-code flow -- direct port of Android's
/// `data/auth/OAuthFlow.kt`. Same non-standard shape as the Android app, because the server
/// itself is non-standard: no PKCE (`code_challenge`/`code_verifier` unsupported), no OIDC
/// discovery document (endpoints are hardcoded), no refresh tokens (confirmed server-side that
/// access tokens never expire).
///
/// `ASWebAuthenticationSession` replaces Custom Tabs *and* Android's separate
/// `OAuthRedirectActivity` in one step: its completion handler is handed the callback URL
/// directly once the browser sheet navigates to `pl.larpnet.ios://oauth?...`, so there is no
/// "redirect-catcher" screen to write, and no back-stack cleanup equivalent to Android's
/// `FLAG_ACTIVITY_CLEAR_TOP` fix is needed either.
@MainActor
final class OAuthFlow: NSObject {
    private let tokenStore: TokenStore
    private let authAPIFactory: (URL) -> AuthAPI
    private var activeSession: ASWebAuthenticationSession?

    static let redirectURI = "pl.larpnet.ios://oauth"
    static let callbackScheme = "pl.larpnet.ios"

    init(tokenStore: TokenStore, authAPIFactory: @escaping (URL) -> AuthAPI) {
        self.tokenStore = tokenStore
        self.authAPIFactory = authAPIFactory
    }

    enum OAuthError: Error {
        case stateMismatch
        case missingCode
        case cancelled
    }

    /// Runs the full flow end to end: register-or-reuse the app, present the authorize page,
    /// exchange the returned code, persist the access token. Throws on any failure; on success
    /// `tokenStore.isLoggedIn` is true.
    func login(instanceInput: String) async throws {
        guard let baseURL = InstanceURL.normalize(instanceInput) else {
            throw NetworkError.invalidURL
        }
        let authAPI = authAPIFactory(baseURL)
        let registration = try await ensureAppRegistered(baseURL: baseURL, authAPI: authAPI)

        let state = UUID().uuidString
        let authorizeURL = try buildAuthorizeURL(baseURL: baseURL, clientId: registration.clientId, state: state)
        let callbackURL = try await presentAuthSession(url: authorizeURL)

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthError.missingCode
        }
        let query = callbackComponents.queryItems ?? []
        guard let returnedState = query.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw OAuthError.stateMismatch
        }
        guard let code = query.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }

        let token = try await authAPI.exchangeToken(
            clientId: registration.clientId,
            clientSecret: registration.clientSecret,
            redirectURI: Self.redirectURI,
            code: code
        )
        tokenStore.accessToken = token.accessToken
    }

    /// Cached in `TokenStore` so re-login to the same instance skips re-registration, same as
    /// Android's `ensureAppRegistered`.
    private func ensureAppRegistered(baseURL: URL, authAPI: AuthAPI) async throws -> AppRegistration {
        if tokenStore.instanceBaseURL == baseURL.absoluteString,
           let clientId = tokenStore.clientId,
           let clientSecret = tokenStore.clientSecret {
            return AppRegistration(id: "", clientId: clientId, clientSecret: clientSecret)
        }
        let registration = try await authAPI.registerApp(clientName: "Larpnet iOS", redirectURI: Self.redirectURI)
        tokenStore.instanceBaseURL = baseURL.absoluteString
        tokenStore.clientId = registration.clientId
        tokenStore.clientSecret = registration.clientSecret
        return registration
    }

    private func buildAuthorizeURL(baseURL: URL, clientId: String, state: String) throws -> URL {
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false
        ) else {
            throw NetworkError.invalidURL
        }
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: AuthAPI.scope),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = comps.url else { throw NetworkError.invalidURL }
        return url
    }

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: OAuthError.cancelled)
                return
            }
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // `false` (the shared, Safari-cookie-sharing mode) means a session cookie from a
            // previous login on this server persists across the app's own logout: the
            // authorize page silently continues as the already-logged-in account instead of
            // showing a fresh login form, skipping username/password *and* TFA, and making it
            // impossible to log in as a different account after logging out. `true` gives
            // every login attempt a clean, cookie-free session instead.
            session.prefersEphemeralWebBrowserSession = true
            self.activeSession = session
            session.start()
        }
    }
}

extension OAuthFlow: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    return window
                }
            }
        }
        return ASPresentationAnchor()
    }
}

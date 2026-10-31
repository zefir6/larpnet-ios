import Foundation
import os

/// Registration for classic Friendica notifications (likes, comments, follows, DMs) with the
/// `larpnet_apns` addon, and the one-time sign-in it needs on older logins.
///
/// `POST /larpnet_apns` requires the OAuth `push` scope, which the server stores on the login
/// token itself (`application-token.push`). Builds before 1.45 never asked for it, so their
/// tokens always got 403 `insufficient_scope` and those notifications fell back to
/// `BackgroundRefresh` polling. The app can't add a scope to an existing token on its own;
/// running the authorize flow again does (Friendica updates the same token in place, so the
/// access token and everything else stays as it was). `needsSignIn` drives the prompt for that.
@MainActor
@Observable
final class ClassicPushStore {
    private(set) var needsSignIn: Bool
    private(set) var isSigningIn = false

    private let tokenStore: TokenStore
    private let friendicaAPI: () throws -> FriendicaAPIClient
    private let oAuthFlow: OAuthFlow
    private static let log = Logger(subsystem: "pl.larpnet.ios", category: "ClassicPush")

    init(tokenStore: TokenStore, friendicaAPI: @escaping () throws -> FriendicaAPIClient, oAuthFlow: OAuthFlow) {
        self.tokenStore = tokenStore
        self.friendicaAPI = friendicaAPI
        self.oAuthFlow = oAuthFlow
        self.needsSignIn = tokenStore.classicPushNeedsSignIn
    }

    /// Best-effort: any failure other than a missing scope just leaves this device on
    /// `BackgroundRefresh`'s polling until the next attempt (next launch / token callback).
    func register(hexToken: String) async {
        do {
            try await friendicaAPI().registerApnsToken(hexToken)
            tokenStore.classicApnsRegisteredToken = hexToken
            setNeedsSignIn(false)
        } catch NetworkError.insufficientScope {
            Self.log.info("larpnet_apns: login token has no push scope")
            setNeedsSignIn(true)
        } catch {
            Self.log.error("larpnet_apns registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Runs the authorize flow again (now asking for `push`), then retries the registration.
    func signIn() async throws {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        try await oAuthFlow.login(instanceInput: tokenStore.instanceBaseURL ?? tokenStore.preferredInstance)
        if let hexToken = tokenStore.apnsDeviceTokenHex {
            await register(hexToken: hexToken)
        } else {
            setNeedsSignIn(false)
        }
    }

    private func setNeedsSignIn(_ value: Bool) {
        needsSignIn = value
        tokenStore.classicPushNeedsSignIn = value
    }
}

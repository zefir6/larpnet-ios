import Foundation
import os

/// In-app account registration: form -> code from the email -> logged in (or "waits for
/// approval"). Port of Android's `ui/register/RegisterViewModel.kt`. The proof that the request
/// comes from this genuine app is App Attest (`AppAttestProvider`); without it the registration
/// is still sent and the server decides (it refuses by default, with `attestation_failed`).
@MainActor
@Observable
final class RegisterViewModel {
    enum Step: Equatable {
        case form
        case code(id: String, email: String, approvalRequired: Bool)
        case approvalPending
        /// Confirmed, but log in the normal way (link used, or no token for this app).
        case logIn
        case loggedIn
    }

    struct Message: Equatable {
        let text: String
        var useWebsite = false
        var isInfo = false
    }

    private(set) var step: Step = .form
    private(set) var busy = false
    private(set) var message: Message?

    var displayName = ""
    var username = ""
    var email = ""
    var password = ""
    var passwordRepeat = ""
    var reason = ""
    var code = ""

    private let appContainer: AppContainer
    private let logger = Logger(subsystem: "pl.larpnet.ios", category: "Registration")

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    /// Same instance choice as the login screen (iOS Settings -> Larpnet can change it).
    var baseURL: URL? { InstanceURL.normalize(appContainer.tokenStore.preferredInstance) }

    var instanceHost: String { baseURL?.host() ?? "larpnet.pl" }

    var passwordsMatch: Bool { passwordRepeat.isEmpty || password == passwordRepeat }

    var canSubmit: Bool {
        !busy && !displayName.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty
            && email.contains("@") && password.count >= 8 && password == passwordRepeat
    }

    var canConfirm: Bool { !busy && code.filter(\.isNumber).count == 6 }

    func submit() {
        guard canSubmit, let baseURL else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                let app = try await appContainer.oAuthFlow.ensureAppRegistered(
                    baseURL: baseURL, authAPI: appContainer.authAPI(baseURL: baseURL)
                )
                let api = appContainer.registrationAPI(baseURL: baseURL)
                let challenge = try await api.challenge(clientId: app.clientId, clientSecret: app.clientSecret).challenge

                var fields = [
                    "client_id": app.clientId,
                    "client_secret": app.clientSecret,
                    "display_name": displayName.trimmingCharacters(in: .whitespaces),
                    "username": username,
                    "email": email.trimmingCharacters(in: .whitespaces),
                    "password": password,
                    "reason": reason.trimmingCharacters(in: .whitespacesAndNewlines),
                    // The terms were accepted on TermsGateView before this screen.
                    "agreement": "true",
                    "locale": Locale.preferredLanguages.first ?? "pl",
                    "platform": "ios",
                    "challenge": challenge,
                ]
                do {
                    let proof = try await AppAttestProvider.attest(challenge: challenge)
                    fields["attestation"] = proof.attestation
                    fields["key_id"] = proof.keyId
                } catch {
                    logger.warning("App Attest unavailable: \(String(describing: error), privacy: .public)")
                }

                let started = try await api.register(fields: fields)
                password = ""
                passwordRepeat = ""
                step = .code(
                    id: started.id,
                    email: started.email ?? email,
                    approvalRequired: started.approvalRequired ?? false
                )
            } catch let failure as RegistrationAPI.Failure {
                message = Message(
                    text: failure.message ?? "Couldn't create the account. Try again.",
                    useWebsite: failure.code == "attestation_failed"
                )
            } catch {
                message = Message(text: "Couldn't create the account. Check your connection and try again.")
            }
        }
    }

    func confirm() {
        guard case .code(let id, _, _) = step, canConfirm, let baseURL,
              let clientId = appContainer.tokenStore.clientId,
              let clientSecret = appContainer.tokenStore.clientSecret else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                let result = try await appContainer.registrationAPI(baseURL: baseURL).confirm(
                    clientId: clientId, clientSecret: clientSecret, id: id, code: code.filter(\.isNumber)
                )
                if result.status == "approval_pending" {
                    step = .approvalPending
                } else if let token = result.accessToken, !token.isEmpty {
                    appContainer.tokenStore.accessToken = token
                    step = .loggedIn
                } else {
                    step = .logIn
                }
            } catch let failure as RegistrationAPI.Failure {
                code = ""
                message = Message(text: failure.message ?? "That didn't work. Try again.")
                if failure.status == 410 { step = .form }
            } catch {
                message = Message(text: "Couldn't reach the server. Check your connection and try again.")
            }
        }
    }

    func resend() {
        guard case .code(let id, _, _) = step, let baseURL,
              let clientId = appContainer.tokenStore.clientId,
              let clientSecret = appContainer.tokenStore.clientSecret else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                _ = try await appContainer.registrationAPI(baseURL: baseURL).resend(
                    clientId: clientId, clientSecret: clientSecret, id: id
                )
                message = Message(text: "We sent a new email. The previous code no longer works.", isInfo: true)
            } catch let failure as RegistrationAPI.Failure {
                message = Message(text: failure.message ?? "Couldn't send the email. Try again later.")
            } catch {
                message = Message(text: "Couldn't reach the server. Check your connection and try again.")
            }
        }
    }

    /// "I clicked the link in the email": confirmed -- log in the normal way, or wait for approval.
    func linkUsed() {
        guard case .code(_, _, let approvalRequired) = step else { return }
        step = approvalRequired ? .approvalPending : .logIn
    }
}

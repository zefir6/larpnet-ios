import MatrixRustSDK
import UserNotifications

/// Runs in its own process (separate from the main app) whenever an APNs alert push for a
/// Matrix message arrives -- Apple's servers only ever see the generic placeholder alert
/// `larpnet_matrix_apns_send()` sends server-side (`aps.alert = {"title": "Larpnet", "body":
/// "New message"}`, `mutable-content: 1`), plus a bare `event_id`/`room_id` at the payload's
/// top level (see that function's doc comment in `friendica-larpnet`). This extension's whole
/// job is to independently log into the *same* Matrix device the main app uses, fetch and
/// decrypt exactly that one event locally via `MatrixRustSDK.NotificationClient`, and replace
/// the placeholder with the real sender/preview before the banner is shown -- the decrypted
/// content itself never leaves this device.
///
/// Reuses the main app's `TokenStore`/`KeychainStore` (shared Keychain access group) and
/// `MatrixSessionPaths` (shared App Group container) to reach the same crypto/session store the
/// main app already has on disk -- see those types' own doc comments for the App Group +
/// Keychain Sharing capabilities this requires on both targets' App IDs. Deliberately does its
/// own minimal `POST /larpnet_matrix` call via a bare `URLSession` rather than pulling in the
/// full `FriendicaAPIClient` -- this target only ever needs three fields off that response, and
/// staying lean here keeps the ~30s extension time budget (`serviceExtensionTimeWillExpire`)
/// from being spent on unrelated client machinery.
/// `@unchecked Sendable`: the system creates one instance of this class per notification and
/// never touches it from more than one place concurrently -- `didReceive`, the `Task` it
/// spawns, and `serviceExtensionTimeWillExpire` never run at the same time in practice, so
/// there's no real data race to guard against, only the strict-concurrency checker's inability
/// to see that from a plain non-`Sendable` class captured across a `Task { ... }` boundary.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()

        // Pull the two plain strings out of `request` before crossing into the `Task` closure --
        // `UNNotificationRequest` itself isn't `Sendable`, so capturing it directly here is what
        // the Swift 6 strict-concurrency checker's "sending parameter risks data races" error
        // was about; these two `String`s are.
        let eventId = request.content.userInfo["event_id"] as? String
        let roomId = request.content.userInfo["room_id"] as? String

        Task {
            await resolveAndDeliver(eventId: eventId, roomId: roomId)
        }
    }

    /// Apple gives this extension a tight, unspecified time budget -- if it's about to run out,
    /// deliver whatever's in `bestAttemptContent` (the original placeholder, if nothing better
    /// was resolved yet) rather than let the notification silently vanish.
    override func serviceExtensionTimeWillExpire() {
        deliver(bestAttemptContent)
    }

    private func resolveAndDeliver(eventId: String?, roomId: String?) async {
        guard
            let eventId, let roomId,
            !eventId.isEmpty, !roomId.isEmpty
        else {
            deliver(bestAttemptContent)
            return
        }

        do {
            let tokenStore = TokenStore()
            guard
                let accessToken = tokenStore.accessToken,
                let instanceBaseURL = tokenStore.instanceBaseURL,
                let deviceId = tokenStore.matrixDeviceId
            else {
                deliver(bestAttemptContent)
                return
            }

            let identity = try await matrixLogin(baseURL: instanceBaseURL, accessToken: accessToken)
            let sessionDir = try MatrixSessionPaths.sessionDirectory(for: identity.userId)
            let client = try await ClientBuilder()
                .homeserverUrl(url: identity.homeserver)
                .sessionPaths(dataPath: sessionDir.path, cachePath: sessionDir.path)
                .build()
            try await client.customLoginWithJwt(jwt: identity.token, initialDeviceName: "larpnet iOS", deviceId: deviceId)

            let notificationClient = try await client.notificationClient(processSetup: .multipleProcesses)
            let status = try await notificationClient.getNotification(roomId: roomId, eventId: eventId)

            guard case .event(let item) = status, let preview = MatrixNotificationPreview.build(from: item) else {
                deliver(bestAttemptContent)
                return
            }

            let mutated = bestAttemptContent ?? UNMutableNotificationContent()
            mutated.title = preview.title
            mutated.body = preview.body
            deliver(mutated)
        } catch {
            deliver(bestAttemptContent)
        }
    }

    /// Only the three fields this extension actually needs off `POST /larpnet_matrix`'s JSON
    /// response -- a deliberately narrower decode than the main app's `MatrixLoginResponse`
    /// (which also carries `contacts`/`push_gateway_url`, irrelevant here), so this target has
    /// no dependency on that model file.
    private struct LoginIdentity: Decodable {
        let userId: String
        let homeserver: String
        let token: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case homeserver
            case token
        }
    }

    private func matrixLogin(baseURL: String, accessToken: String) async throws -> LoginIdentity {
        guard let url = URL(string: "larpnet_matrix", relativeTo: URL(string: baseURL)) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(LoginIdentity.self, from: data)
    }

    private func deliver(_ content: UNMutableNotificationContent?) {
        guard let contentHandler else { return }
        self.contentHandler = nil
        contentHandler(content ?? UNMutableNotificationContent())
    }
}

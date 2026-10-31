import Foundation
import MatrixRustSDK
import os

/// Fetches and decrypts the one event a chat push is about, for `NotificationServiceExtension`
/// -- in this file rather than that target so the main app's debug builds can run the same
/// code on demand (`DebugChatPush`): a simulated push (`simctl push`) never starts the
/// extension. Opens the same Matrix device the main app uses: restores the session the main
/// app saved (`MatrixSavedSession`), or logs in to that device when there is none or it
/// doesn't work. Logs every outcome under `ChatPush`, like larpnet-android's `ChatPush`.
///
/// Deliberately does its own minimal `POST /larpnet_matrix` call via a bare `URLSession` rather
/// than pulling in the full `FriendicaAPIClient` -- the extension only needs three fields off
/// that response, and staying lean keeps its ~30s time budget for the fetch itself.
enum MatrixChatPushResolver {
    private static let log = Logger(subsystem: "pl.larpnet.ios", category: "ChatPush")

    static func preview(roomId: String, eventId: String, tokenStore: TokenStore) async -> (title: String, body: String)? {
        let started = Date()
        var status: NotificationStatus?
        var path = "restored"
        if let client = await restoredClient(tokenStore) {
            status = await notificationStatus(client, roomId: roomId, eventId: eventId)
        }
        // No saved session, or it no longer works (e.g. its token was replaced): log in instead.
        if status == nil {
            path = "login"
            do {
                if let client = try await loggedInClient(tokenStore) {
                    status = await notificationStatus(client, roomId: roomId, eventId: eventId)
                }
            } catch {
                log.error("room=\(roomId, privacy: .public) login failed: \(String(describing: error), privacy: .public)")
            }
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        guard case .event(let item) = status, let preview = MatrixNotificationPreview.build(from: item) else {
            log.warning("room=\(roomId, privacy: .public) event=\(eventId, privacy: .public) decrypt=failed via=\(path, privacy: .public) ms=\(ms), showing the placeholder")
            return nil
        }
        log.info("room=\(roomId, privacy: .public) event=\(eventId, privacy: .public) decrypt=ok via=\(path, privacy: .public) ms=\(ms)")
        return preview
    }

    private static func notificationStatus(_ client: Client, roomId: String, eventId: String) async -> NotificationStatus? {
        do {
            let notificationClient = try await client.notificationClient(processSetup: .multipleProcesses)
            return try await notificationClient.getNotification(roomId: roomId, eventId: eventId)
        } catch {
            log.error("room=\(roomId, privacy: .public) getNotification failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The main app's own session, restored without any network round trip -- the normal case.
    private static func restoredClient(_ tokenStore: TokenStore) async -> Client? {
        guard let saved = MatrixSavedSession.load(from: tokenStore),
              saved.deviceId == tokenStore.matrixDeviceId,
              let sessionDir = try? MatrixSessionPaths.sessionDirectory(for: saved.userId),
              let client = try? await MatrixClientConfig.builder(homeserver: saved.homeserverUrl, sessionDir: sessionDir).build()
        else { return nil }
        do {
            try await client.restoreSession(session: saved.session)
            return client
        } catch {
            log.error("restoreSession failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// JWT login into the main app's device -- for an install whose main app hasn't saved a
    /// session yet (first push after updating from a build before `MatrixSavedSession`). Saves
    /// the result so the next push restores it instead.
    private static func loggedInClient(_ tokenStore: TokenStore) async throws -> Client? {
        guard
            let accessToken = tokenStore.accessToken,
            let instanceBaseURL = tokenStore.instanceBaseURL,
            let deviceId = tokenStore.matrixDeviceId
        else { return nil }

        let identity = try await matrixLogin(baseURL: instanceBaseURL, accessToken: accessToken)
        let sessionDir = try MatrixSessionPaths.sessionDirectory(for: identity.userId)
        let client = try await MatrixClientConfig.builder(homeserver: identity.homeserver, sessionDir: sessionDir).build()
        try await client.customLoginWithJwt(jwt: identity.token, initialDeviceName: "larpnet iOS", deviceId: deviceId)
        if let session = try? client.session() {
            MatrixSavedSession(session).save(to: tokenStore)
        }
        return client
    }

    /// Only the three fields needed off `POST /larpnet_matrix`'s JSON response -- a narrower
    /// decode than the main app's `MatrixLoginResponse`, so the extension doesn't need that file.
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

    private static func matrixLogin(baseURL: String, accessToken: String) async throws -> LoginIdentity {
        guard let url = URL(string: "larpnet_matrix", relativeTo: URL(string: baseURL)) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(LoginIdentity.self, from: data)
    }
}

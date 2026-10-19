import UserNotifications

/// Runs in its own process (separate from the main app) whenever an APNs alert push for a
/// Matrix message arrives -- Apple's servers only ever see the generic placeholder alert
/// `larpnet_matrix_apns_send()` sends server-side (`aps.alert = {"title": "Larpnet", "body":
/// "New message"}`, `mutable-content: 1`), plus a bare `event_id`/`room_id` at the payload's
/// top level (see that function's doc comment in `friendica-larpnet`). This extension's whole
/// job is to open the *same* Matrix device the main app uses (restoring the session it saved,
/// `MatrixSavedSession`, or failing that logging in to it), fetch and
/// decrypt exactly that one event locally via `MatrixRustSDK.NotificationClient`, and replace
/// the placeholder with the real sender/preview before the banner is shown -- the decrypted
/// content itself never leaves this device.
///
/// Reuses the main app's `TokenStore`/`KeychainStore` (shared Keychain access group) and
/// `MatrixSessionPaths` (shared App Group container) to reach the same crypto/session store the
/// main app already has on disk -- see those types' own doc comments for the App Group +
/// Keychain Sharing capabilities this requires on both targets' App IDs. The fetch itself is
/// `MatrixChatPushResolver`, shared with the main app so a debug build can run it on demand.
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
        // One Notification Center group per room, also what ChatThreadViewModel clears when the
        // room is opened. aps.badge (the server's unread-room count) passes through untouched.
        if let roomId = request.content.userInfo["room_id"] as? String, !roomId.isEmpty {
            bestAttemptContent?.threadIdentifier = roomId
        }

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

        guard let preview = await MatrixChatPushResolver.preview(roomId: roomId, eventId: eventId, tokenStore: TokenStore()) else {
            deliver(bestAttemptContent)
            return
        }

        let mutated = bestAttemptContent ?? UNMutableNotificationContent()
        mutated.title = preview.title
        mutated.body = preview.body
        deliver(mutated)
    }

    private func deliver(_ content: UNMutableNotificationContent?) {
        guard let contentHandler else { return }
        self.contentHandler = nil
        contentHandler(content ?? UNMutableNotificationContent())
    }
}

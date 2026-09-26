import Foundation
import MatrixRustSDK

/// Turns a decrypted `NotificationItem` into a title/body pair ready to show in a local
/// notification -- shared between `MatrixClientStore` (not currently a caller, but kept here
/// rather than duplicated) and `NotificationServiceExtension`, which is the actual caller: both
/// targets list this file in their `sources` (see project.yml). Never touches the push payload
/// itself, which only ever carries `event_id`/`room_id` (see `larpnet_matrix_push_notify()`'s
/// own doc comment for why).
enum MatrixNotificationPreview {
    static func build(from item: NotificationItem) -> (title: String, body: String)? {
        // No raw mxid available here to run through a Friendica-name lookup the way room-list
        // rows do (`NotificationSenderInfo` only carries a display name, not a user id) --
        // relying instead on `larpnet_matrix_sync_profile()`'s own server-side sync (throttled
        // hourly, or via its cron hook for everyone) already having given this sender a real
        // Matrix displayname by the time push notifications matter.
        guard let senderName = item.senderInfo.displayName, !senderName.isEmpty else { return nil }
        let roomName = item.roomInfo.displayName
        let title = (item.roomInfo.isDm || roomName.isEmpty) ? senderName : "\(senderName) (\(roomName))"

        let messageBody: String?
        switch item.event {
        case .invite:
            messageBody = "Zaproszenie do rozmowy"
        case .timeline(let event):
            messageBody = bodyFor(content: try? event.content())
        }
        guard let messageBody else { return nil }

        return (title, messageBody)
    }

    private static func bodyFor(content: TimelineEventContent?) -> String? {
        guard let content, case .messageLike(let messageLike) = content else { return nil }
        switch messageLike {
        case .roomMessage(let messageType, _):
            switch messageType {
            case .text(let content): return content.body
            case .image: return "📷 Zdjęcie"
            case .file: return "📎 Plik"
            case .audio: return "🎤 Nagranie"
            case .video: return "🎬 Wideo"
            default: return "Nowa wiadomość"
            }
        case .roomEncrypted:
            return "🔒"
        default:
            return nil
        }
    }
}

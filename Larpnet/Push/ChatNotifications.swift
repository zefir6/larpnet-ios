import Foundation
import os
import UserNotifications

/// Removes delivered chat notifications once their room is read -- on this device (opening
/// the room, "Mark as read", muting) or anywhere else (the next sync shows the room as read).
/// Chat notifications are the ones `NotificationServiceExtension` groups under
/// `threadIdentifier = roomId`. Same rules as larpnet-android's `PushNotifications.cancelChat`
/// and `reconcileChat`.
enum ChatNotifications {
    /// A push can be shown before the sync that carries its message lands, while the room still
    /// looks read locally -- a notification younger than this is never removed by `reconcile`.
    private static let reconcileGrace: TimeInterval = 15
    private static let log = Logger(subsystem: "pl.larpnet.ios", category: "ChatNotifications")

    static func remove(roomId: String) async {
        await remove { $0.request.content.threadIdentifier == roomId }
    }

    /// After a sync response: removes the notifications of `readRoomIds` (joined rooms with
    /// nothing unread, or muted) that were delivered more than `reconcileGrace` ago.
    static func reconcile(readRoomIds: Set<String>) async {
        let cutoff = Date().addingTimeInterval(-reconcileGrace)
        await remove { readRoomIds.contains($0.request.content.threadIdentifier) && $0.date < cutoff }
    }

    private static func remove(where matches: (UNNotification) -> Bool) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.deliveredNotifications().filter(matches).map(\.request.identifier)
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
        log.info("removed \(ids.count) delivered chat notification(s)")
    }
}

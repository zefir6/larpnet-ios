#if DEBUG
import Foundation
import os
import UserNotifications

/// Debug builds only: runs the notification extension's fetch-and-decrypt
/// (`MatrixChatPushResolver`) for a chat event and posts the result the way the extension
/// would, because a simulated push (`xcrun simctl push`) never starts the extension. Driven by
/// launch arguments:
///
///     xcrun simctl launch booted pl.larpnet.ios -debugChatPushList YES
///     xcrun simctl launch booted pl.larpnet.ios -debugChatPushRoom '!room:id' [-debugChatPushNth 0]
///
/// The first logs every room (unread count, newest incoming event); the second "pushes" the
/// nth newest incoming message of that room. Output: `log stream --predicate
/// 'subsystem == "pl.larpnet.ios"'` (categories `DebugChatPush` and `ChatPush`).
@MainActor
enum DebugChatPush {
    private static let log = Logger(subsystem: "pl.larpnet.ios", category: "DebugChatPush")

    static func runIfRequested(appContainer: AppContainer) async {
        let defaults = UserDefaults.standard
        let store = appContainer.matrixClientStore
        if defaults.bool(forKey: "debugChatPushList") {
            for room in (try? await store.rooms()) ?? [] {
                let newest = await incomingEventIds(store, roomId: room.id).first ?? "-"
                log.info("room \(room.id, privacy: .public) name=\(room.name, privacy: .public) unread=\(room.unreadCount) newestIncoming=\(newest, privacy: .public)")
            }
        }
        guard let roomId = defaults.string(forKey: "debugChatPushRoom") else { return }
        let ids = await incomingEventIds(store, roomId: roomId)
        let nth = defaults.integer(forKey: "debugChatPushNth")
        guard ids.indices.contains(nth) else {
            log.warning("no incoming message #\(nth) in \(roomId, privacy: .public)")
            return
        }
        log.info("simulating push room=\(roomId, privacy: .public) event=\(ids[nth], privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = "Larpnet"
        content.body = "New message"
        content.threadIdentifier = roomId
        content.userInfo = ["room_id": roomId, "event_id": ids[nth]]
        if let preview = await MatrixChatPushResolver.preview(roomId: roomId, eventId: ids[nth], tokenStore: appContainer.tokenStore) {
            content.title = preview.title
            content.body = preview.body
        }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    /// Incoming message event ids of `roomId`, newest first.
    private static func incomingEventIds(_ store: MatrixClientStore, roomId: String) async -> [String] {
        guard let handle = try? await store.openTimeline(roomId: roomId) else { return [] }
        defer { handle.close() }
        for await snapshot in handle.messages {
            return snapshot.filter { !$0.isOwn }.compactMap(\.eventId).reversed()
        }
        return []
    }
}
#endif

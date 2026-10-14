import Foundation

/// Shared chat state outside any one screen:
/// - `totalUnreadCount`: rooms with unread messages (muted excluded), for the Chat tab badge --
///   written by `MatrixClientStore.onUnreadCountChange` (wired in `LarpnetApp`) after every
///   sync, so it's right before the Chat tab is ever opened.
/// - `visibleRoomId`: the room `ChatThreadView` is showing while the app is active --
///   `AppDelegate` shows no banner for a push from that room.
/// - `pendingRoomId`: a room to open from a tapped chat notification (`RootView` presents it).
@MainActor
@Observable
final class ChatBadgeStore {
    var totalUnreadCount = 0
    var visibleRoomId: String?
    var pendingRoomId: String?
}

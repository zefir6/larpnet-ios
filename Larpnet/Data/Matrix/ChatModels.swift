import Foundation

/// One row in the chat room list -- `MatrixClientStore.rooms()`'s output shape, already
/// resolved to display-ready fields so `ChatViewModel`/`ChatView` never touch MatrixRustSDK
/// types directly (mirrors how `Conversation`/`Account` keep Messages' UI layer decoupled from
/// the raw Mastodon API JSON shape).
struct ChatRoom: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let preview: String?
    let timestamp: Date?
    /// "Interesting" unread message count from `Room.roomInfo().numUnreadMessages` -- drives
    /// the room row's unread styling and the Chat tab's badge total.
    let unreadCount: Int
}

/// One message in a room's timeline -- `ChatTimelineHandle`'s output shape.
struct ChatMessage: Identifiable, Sendable, Hashable {
    let id: String
    let isOwn: Bool
    let body: String
    let timestamp: Date
    /// Sender mxid and display name, from `EventTimelineItem.sender`/`senderProfile` -- nil for
    /// `isOwn` messages (the composer already knows who "you" are). Used to attribute and
    /// cluster incoming messages by sender in group rooms.
    let senderId: String?
    let senderDisplayName: String?
}

/// One other member of a room, display-ready -- `MatrixClientStore.roomInfo()`'s member list.
struct ChatRoomMember: Identifiable, Sendable, Hashable {
    let userId: String
    let displayName: String
    var id: String { userId }
}

/// `MatrixClientStore.roomInfo()`'s output shape -- mirrors the web client's `RoomInfoModal.jsx`
/// (`others`/`isGroup`/`room.name`).
struct ChatRoomInfo: Sendable {
    let roomId: String
    let rawName: String
    let isGroup: Bool
    let members: [ChatRoomMember]
}

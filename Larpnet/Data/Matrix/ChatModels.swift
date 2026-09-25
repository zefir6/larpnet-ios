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
}

/// One message in a room's timeline -- `ChatTimelineHandle`'s output shape.
struct ChatMessage: Identifiable, Sendable, Hashable {
    let id: String
    let isOwn: Bool
    let body: String
    let timestamp: Date
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

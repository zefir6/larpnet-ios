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
    /// Synapse's notification count (`MatrixClientStore.unreadCount(of:)`) -- drives
    /// the room row's unread styling and the Chat tab's badge. Always 0 for a `muted` room, same
    /// as Synapse's own notification count (and so every other client's badge).
    let unreadCount: Int
    /// `mxc://` room avatar, from `Room.avatarUrl()` (falling back to the 1:1 hero's own avatar
    /// when the room itself has none) -- resolved to a real image via
    /// `MatrixClientStore.avatarThumbnail(mxcUrl:)`, not just an initials placeholder.
    let avatarUrl: String?
    /// The other member's mxid for a 1:1 room without its own avatar, nil otherwise -- the
    /// Friendica profile photo is looked up from this first (see
    /// `MatrixClientStore.friendicaAvatarURL(userId:)`).
    var peerUserId: String?
    /// Muted via the shared per-room mute (`POST larpnet_matrix/mute`, a Matrix push rule) --
    /// see `MatrixClientStore.muteStates(_:)`.
    var muted: Bool = false
    /// When a timed mute ends; nil when permanent or not muted.
    var mutedUntil: Date?
}

/// One message in a room's timeline -- `ChatTimelineHandle`'s output shape.
struct ChatMessage: Identifiable, Sendable, Hashable {
    let id: String
    let isOwn: Bool
    let body: String
    /// The event's id once the server has it; nil for a local echo still sending. What a read
    /// receipt points at (see `ChatTimelineHandle.sendReadReceipt(eventId:)`).
    let eventId: String?
    let timestamp: Date
    /// Sender mxid and display name, from `EventTimelineItem.sender`/`senderProfile` -- nil for
    /// `isOwn` messages (the composer already knows who "you" are). Used to attribute and
    /// cluster incoming messages by sender in group rooms.
    let senderId: String?
    let senderDisplayName: String?
    /// `mxc://` sender avatar from the same `senderProfile`, nil for `isOwn` messages.
    let senderAvatarUrl: String?
    /// True for a message whose content the SDK couldn't decrypt (missing/not-yet-restored
    /// room key -- see `MatrixClientStore.resetRecovery()`'s doc comment for the usual cause).
    /// `ChatThreadView` renders this as a distinct inline note instead of a normal bubble;
    /// `body` is empty and unused in this case.
    let isUndecryptable: Bool
}

/// One other member of a room, display-ready -- `MatrixClientStore.roomInfo()`'s member list.
struct ChatRoomMember: Identifiable, Sendable, Hashable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    var id: String { userId }
}

/// `MatrixClientStore.roomInfo()`'s output shape -- mirrors the web client's `RoomInfoModal.jsx`
/// (`others`/`isGroup`/`room.name`).
struct ChatRoomInfo: Sendable {
    let roomId: String
    let rawName: String
    let isGroup: Bool
    let members: [ChatRoomMember]
    /// The room's own `mxc://` avatar, if one is set (group rooms only, in practice).
    var avatarUrl: String?
}

/// Chat name style setting -- `rawValue` is what's stored under `defaultsKey`, same strings as
/// larpnet-android's `ChatNameDisplay`.
enum ChatNameDisplay: String, CaseIterable, Sendable {
    case full
    case handle
    case both

    static let defaultsKey = "chat_name_display"

    static var current: ChatNameDisplay {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ChatNameDisplay.init(rawValue:)) ?? .full
    }
}

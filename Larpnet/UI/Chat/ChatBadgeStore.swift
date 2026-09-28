import Foundation

/// Total unread-message count across all Matrix chat rooms, for the Chat tab's badge --
/// `ChatViewModel` writes to this every time it refreshes the room list, and `RootView` reads it
/// to badge the tab regardless of whether Chat is the currently-visible tab.
@MainActor
@Observable
final class ChatBadgeStore {
    var totalUnreadCount = 0
}

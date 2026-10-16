import Foundation
import UserNotifications

/// Either an already-known room (opened from the room list, which already has its display
/// name), a bare Friendica nickname (opened from a profile's "Chat" button or the new-chat
/// picker), or an already-fully-qualified Matrix address typed directly (the new-chat picker's
/// "enter a Matrix address" fallback -- works for a federated address on a different homeserver
/// too, which the local-account search could never find) -- `ChatThreadViewModel.load()`
/// resolves either of the latter two to a room id itself via `MatrixClientStore.
/// openOrCreateDirectRoom()`, creating the room on first contact.
enum ChatThreadTarget: Hashable {
    case room(id: String, name: String)
    case nickname(String)
    case matrixId(String)
}

/// Direct port of `ConversationThreadViewModel`'s shape for native Matrix chat: loads a room's
/// timeline, tracks a send box. Unlike Friendica DMs, the timeline here is a live subscription
/// (`ChatTimelineHandle.messages`), not a one-shot fetch -- `close()` must be called when the
/// screen goes away (see `ChatThreadView`'s `onDisappear`) to stop that subscription.
@MainActor
@Observable
final class ChatThreadViewModel {
    private(set) var roomName: String?
    private(set) var roomId: String?
    private(set) var messages: [ChatMessage] = []
    /// Whether this room has more than one other member -- drives whether message clusters show
    /// a sender avatar/name (group chats only; a 1:1's incoming sender is already obvious from
    /// the room itself).
    private(set) var isGroup = false
    /// Header avatar: the room's own `mxc://` avatar (groups) or the 1:1 partner's, plus the
    /// partner's mxid for the Friendica-photo lookup (see `MatrixAvatarView`).
    private(set) var avatarUrl: String?
    private(set) var peerUserId: String?
    private(set) var isLoading = false
    private(set) var isSending = false
    var draft: String = ""
    var errorMessage: String?

    /// No room to send into at all (as opposed to a room that loaded fine but a later `send()`
    /// failed) -- `ChatThreadView` uses this to show a clear failure state and hide the
    /// composer, rather than the misleading "empty, ready to type" look a bare `errorMessage`
    /// next to a still-active composer gives.
    var failedToLoad: Bool { !isLoading && roomId == nil && errorMessage != nil }

    private let target: ChatThreadTarget
    private let appContainer: AppContainer
    private var handle: ChatTimelineHandle?
    private var messagesTask: Task<Void, Never>?
    /// On screen with the app active -- read receipts only go out then, so a message that
    /// arrives while the app is in the background stays unread.
    private var isVisible = false
    private var lastReadMessageId: String?
    private var isMarkingRead = false

    init(target: ChatThreadTarget, appContainer: AppContainer) {
        self.target = target
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resolvedRoomId: String
            switch target {
            case .room(let id, let name):
                resolvedRoomId = id
                roomName = name
                // Opened from a chat notification, which only knows the room id.
                if name.isEmpty {
                    roomName = await appContainer.matrixClientStore.roomDisplayName(roomId: id)
                }
            case .nickname(let nickname):
                roomName = nickname
                resolvedRoomId = try await appContainer.matrixClientStore.openOrCreateDirectRoom(nickname: nickname)
                // Placeholder only: a profile's "Chat" button knows just this. Swap in the same
                // name the room list shows (full name by default).
                roomName = await appContainer.matrixClientStore.roomDisplayName(roomId: resolvedRoomId) ?? roomName
            case .matrixId(let matrixId):
                roomName = matrixId
                resolvedRoomId = try await appContainer.matrixClientStore.openOrCreateDirectRoom(matrixId: matrixId)
                // Placeholder only: a profile's "Chat" button knows just this. Swap in the same
                // name the room list shows (full name by default).
                roomName = await appContainer.matrixClientStore.roomDisplayName(roomId: resolvedRoomId) ?? roomName
            }
            roomId = resolvedRoomId
            if isVisible { setVisible(true) }
            let info = try? await appContainer.matrixClientStore.roomInfo(roomId: resolvedRoomId)
            isGroup = info?.isGroup ?? false
            let peer = isGroup ? nil : info?.members.first
            avatarUrl = info?.avatarUrl ?? peer?.avatarUrl
            peerUserId = peer?.userId
            let newHandle = try await appContainer.matrixClientStore.openTimeline(roomId: resolvedRoomId)
            handle = newHandle
            messagesTask = Task { [weak self] in
                for await snapshot in newHandle.messages {
                    self?.messages = snapshot
                    self?.markReadIfVisible()
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func send() async {
        guard let handle, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await handle.send(text: draft)
            draft = ""
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Called by the view on appear/disappear and scene-phase changes.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        let badgeStore = appContainer.chatBadgeStore
        if visible, let roomId {
            badgeStore.visibleRoomId = roomId
            lastReadMessageId = nil
            markReadIfVisible()
            Task { await Self.removeDeliveredNotifications(roomId: roomId) }
        } else if !visible, badgeStore.visibleRoomId == roomId {
            badgeStore.visibleRoomId = nil
        }
    }

    /// Read receipt for the newest message, once per new message while on screen. Deliberately
    /// does *not* set `lastReadMessageId` until `sendReadReceipt` actually succeeds: marking it
    /// read locally before the server confirms would permanently poison the `newest !=
    /// lastReadMessageId` guard above on a transient failure (network hiccup, sync loop
    /// mid-restart) -- the room's unread bubble would then never clear until a newer message
    /// bumped `newest` to a different id, exactly the "opening the conversation doesn't clear
    /// the badge" symptom reported 2026-10-17. Same class of bug as this app's other
    /// local-cache-vs-server-truth mismatches -- see `resetRecovery()`'s doc comment.
    private func markReadIfVisible() {
        guard isVisible, !isMarkingRead, let handle,
              let newest = messages.last(where: { $0.eventId != nil })?.eventId,
              newest != lastReadMessageId else { return }
        isMarkingRead = true
        Task {
            defer { isMarkingRead = false }
            do {
                try await handle.sendReadReceipt(eventId: newest)
                lastReadMessageId = newest
            } catch {
                // Left unset on purpose -- see doc comment above. The next message update (or
                // re-opening the thread) retries.
            }
        }
    }

    /// The NSE groups a room's pushes under `threadIdentifier = roomId`; opening the room
    /// clears them from Notification Center.
    private static func removeDeliveredNotifications(roomId: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.deliveredNotifications()
            .filter { $0.request.content.threadIdentifier == roomId }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func close() {
        messagesTask?.cancel()
        handle?.close()
    }
}

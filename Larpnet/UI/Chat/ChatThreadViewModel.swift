import Foundation

/// Either an already-known room (opened from the room list, which already has its display
/// name) or a bare Friendica nickname (opened from a profile's "Chat" button or the new-chat
/// picker) -- `ChatThreadViewModel.load()` resolves the latter to a room id itself via
/// `MatrixClientStore.openOrCreateDirectRoom()`, creating the room on first contact.
enum ChatThreadTarget: Hashable {
    case room(id: String, name: String)
    case nickname(String)
}

/// Direct port of `ConversationThreadViewModel`'s shape for native Matrix chat: loads a room's
/// timeline, tracks a send box. Unlike Friendica DMs, the timeline here is a live subscription
/// (`ChatTimelineHandle.messages`), not a one-shot fetch -- `close()` must be called when the
/// screen goes away (see `ChatThreadView`'s `onDisappear`) to stop that subscription.
@MainActor
@Observable
final class ChatThreadViewModel {
    private(set) var roomName: String?
    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var draft: String = ""
    var errorMessage: String?

    private let target: ChatThreadTarget
    private let appContainer: AppContainer
    private var handle: ChatTimelineHandle?
    private var messagesTask: Task<Void, Never>?

    init(target: ChatThreadTarget, appContainer: AppContainer) {
        self.target = target
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let roomId: String
            switch target {
            case .room(let id, let name):
                roomId = id
                roomName = name
            case .nickname(let nickname):
                roomName = nickname
                roomId = try await appContainer.matrixClientStore.openOrCreateDirectRoom(nickname: nickname)
            }
            let newHandle = try await appContainer.matrixClientStore.openTimeline(roomId: roomId)
            handle = newHandle
            messagesTask = Task { [weak self] in
                for await snapshot in newHandle.messages {
                    self?.messages = snapshot
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

    func close() {
        messagesTask?.cancel()
        handle?.close()
    }
}

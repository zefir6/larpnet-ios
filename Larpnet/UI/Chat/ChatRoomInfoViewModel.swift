import Foundation

/// Direct port of the web client's `RoomInfoModal.jsx`: member list with remove, "add member"
/// (delegated to the caller via `AppRoute.addChatMember`, same split as `ChatView`'s
/// `onNewChat`), rename (group rooms only -- see `ChatRoomInfo.isGroup`'s doc comment), and
/// leave (removing yourself).
@MainActor
@Observable
final class ChatRoomInfoViewModel {
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var members: [ChatRoomMember] = []
    private(set) var isGroup = false
    private(set) var rawName = ""
    private(set) var didLeave = false
    private(set) var muted = false
    /// When a timed mute ends; nil when permanent or not muted.
    private(set) var mutedUntil: Date?
    var nameInput = ""
    var errorMessage: String?

    let roomId: String
    private let appContainer: AppContainer

    init(roomId: String, appContainer: AppContainer) {
        self.roomId = roomId
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await appContainer.matrixClientStore.roomInfo(roomId: roomId)
            members = info.members
            isGroup = info.isGroup
            rawName = info.rawName
            nameInput = info.rawName
            (muted, mutedUntil) = await appContainer.matrixClientStore.muteState(roomId: roomId)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func rename() async {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != rawName else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await appContainer.matrixClientStore.renameRoom(roomId: roomId, name: trimmed)
            rawName = trimmed
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func remove(userId: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await appContainer.matrixClientStore.removeMember(roomId: roomId, userId: userId)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Mutes for `duration` from now, or until unmuted when nil.
    func mute(for duration: TimeInterval?) async {
        await updateMute { try await $0.muteRoom(roomId: self.roomId, until: duration.map { Date().addingTimeInterval($0) }) }
    }

    func unmute() async {
        await updateMute { try await $0.unmuteRoom(roomId: self.roomId) }
    }

    private func updateMute(_ call: (MatrixClientStore) async throws -> [String: Date?]) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let mutes = try await call(appContainer.matrixClientStore)
            muted = mutes.keys.contains(roomId)
            mutedUntil = mutes[roomId].flatMap { $0 }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func leave() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await appContainer.matrixClientStore.leaveRoom(roomId: roomId)
            errorMessage = nil
            didLeave = true
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

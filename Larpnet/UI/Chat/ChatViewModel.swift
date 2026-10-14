import Foundation

/// Room list for native Matrix chat -- shaped like `ConversationsViewModel` (Friendica DMs),
/// but backed by `MatrixClientStore` instead of the Mastodon-API conversations endpoint.
/// Refreshes live via `roomListUpdates()` (fed by the SDK's own background sync loop) rather
/// than pull-to-refresh alone, since there's no Link-header pagination here to drive a
/// "load more" gesture off of.
@MainActor
@Observable
final class ChatViewModel {
    private(set) var rooms: [ChatRoom] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// nil once resolved (nothing to show) -- see `MatrixClientStore.ensureEncryption()`.
    private(set) var recoveryPrompt: MatrixClientStore.RecoveryPromptKind?

    private let appContainer: AppContainer
    private var updatesTask: Task<Void, Never>?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard rooms.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await appContainer.matrixClientStore.consolidateDuplicateDirectRooms()
        await refresh()
        subscribeToUpdates()
        // Standard encryption mode unlocks silently with the server-held passphrase; only
        // private mode (or a legacy key on a locked device) yields a prompt here.
        recoveryPrompt = try? await appContainer.matrixClientStore.ensureEncryption()
    }

    func dismissRecoveryPrompt() {
        recoveryPrompt = nil
    }

    func refresh() async {
        do {
            // rooms() also updates the badge, via MatrixClientStore.onUnreadCountChange.
            rooms = try await appContainer.matrixClientStore.rooms()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// "Delete chat" -- Matrix has no server-side delete for a room's history, only leaving it
    /// (per-member, standard Matrix semantics: your own local copy of the timeline stays
    /// readable, but the room disappears from your list and you stop receiving new messages;
    /// rejoining a 1:1 later starts a fresh room via `openOrCreateDirectRoom`). Removes the row
    /// optimistically so the swipe action feels immediate rather than waiting on the leave
    /// round-trip; `refresh()` (also driven by the live room-list update this triggers) is the
    /// source of truth if it fails.
    func leaveRoom(_ room: ChatRoom) async {
        rooms.removeAll { $0.id == room.id }
        do {
            try await appContainer.matrixClientStore.leaveRoom(roomId: room.id)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            await refresh()
        }
    }

    /// Mutes `room` for `duration` (nil = until unmuted) from the row's context menu. The
    /// server's answer is applied to the row at once; sync confirms it shortly after.
    func mute(_ room: ChatRoom, for duration: TimeInterval?) async {
        await updateMute { try await $0.muteRoom(roomId: room.id, until: duration.map { Date().addingTimeInterval($0) }) }
    }

    func unmute(_ room: ChatRoom) async {
        await updateMute { try await $0.unmuteRoom(roomId: room.id) }
    }

    private func updateMute(_ call: (MatrixClientStore) async throws -> [String: Date?]) async {
        do {
            let mutes = try await call(appContainer.matrixClientStore)
            rooms = rooms.map { room in
                var updated = room
                updated.muted = mutes.keys.contains(room.id)
                updated.mutedUntil = mutes[room.id].flatMap { $0 }
                return updated
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Started once, on first load -- `MatrixClientStore.roomListUpdates()` only tracks one
    /// subscriber, so a second call here would just replace it, not stack another feed.
    private func subscribeToUpdates() {
        guard updatesTask == nil else { return }
        let stream = appContainer.matrixClientStore.roomListUpdates()
        updatesTask = Task { [weak self] in
            for await _ in stream {
                await self?.refresh()
            }
        }
    }
}

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

    private let appContainer: AppContainer
    private var updatesTask: Task<Void, Never>?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard rooms.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await refresh()
        subscribeToUpdates()
    }

    func refresh() async {
        do {
            rooms = try await appContainer.matrixClientStore.rooms()
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

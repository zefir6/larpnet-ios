import Foundation

/// Direct port of Android's `ui/messages/ConversationsViewModel.kt`: DM conversation list
/// (Link-header paginated), swipe-to-delete.
@MainActor
@Observable
final class ConversationsViewModel {
    private(set) var conversations: [Conversation] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var nextMaxId: String?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard conversations.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await refresh()
    }

    func refresh() async {
        do {
            let page = try await appContainer.friendicaAPI().conversations()
            conversations = page.items
            nextMaxId = page.nextMaxId
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadMore() async {
        guard let maxId = nextMaxId else { return }
        do {
            let page = try await appContainer.friendicaAPI().conversations(maxId: maxId)
            conversations.append(contentsOf: page.items)
            nextMaxId = page.nextMaxId
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        Task { try? await appContainer.friendicaAPI().deleteConversation(id: conversation.id) }
    }
}

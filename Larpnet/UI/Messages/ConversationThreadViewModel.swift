import Foundation

/// Direct port of Android's `ui/messages/ConversationThreadViewModel.kt`: full 1:1 message
/// history via the Twitter-compat endpoints, send box, marks the conversation read on open.
@MainActor
@Observable
final class ConversationThreadViewModel {
    private(set) var account: Account?
    private(set) var messages: [DirectMessage] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var draft: String = ""
    var errorMessage: String?

    private let accountId: String
    private let conversationId: String?
    private let appContainer: AppContainer

    init(accountId: String, conversationId: String?, appContainer: AppContainer) {
        self.accountId = accountId
        self.conversationId = conversationId
        self.appContainer = appContainer
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = try appContainer.friendicaAPI()
            let resolvedAccount = try await api.getAccount(id: accountId)
            account = resolvedAccount
            let page = try await api.directMessages(profileUrl: resolvedAccount.url)
            messages = page.items.sorted { ($0.parsedCreatedAt ?? .distantPast) < ($1.parsedCreatedAt ?? .distantPast) }
            errorMessage = nil
            if let conversationId {
                _ = try? await api.markConversationRead(id: conversationId)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func send() async {
        guard let account, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let api = try appContainer.friendicaAPI()
            let result = try await api.sendDirectMessage(screenName: account.acct.isEmpty ? account.username : account.acct, text: draft)
            switch result {
            case .sent(let message):
                messages.append(message)
                draft = ""
                errorMessage = nil
            case .failed(let code):
                errorMessage = "Send failed (error \(code))"
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

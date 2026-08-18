import SwiftUI

struct ConversationsView: View {
    @State private var viewModel: ConversationsViewModel
    let onOpenConversation: (Conversation) -> Void
    let onNewMessage: () -> Void

    init(appContainer: AppContainer, onOpenConversation: @escaping (Conversation) -> Void, onNewMessage: @escaping () -> Void) {
        _viewModel = State(initialValue: ConversationsViewModel(appContainer: appContainer))
        self.onOpenConversation = onOpenConversation
        self.onNewMessage = onNewMessage
    }

    var body: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                Button {
                    onOpenConversation(conversation)
                } label: {
                    if let account = conversation.accounts.first {
                        let subtitle: String? = conversation.lastStatus?.content.prefix(80).description
                        AccountRow(account: account, subtitle: subtitle)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) { viewModel.delete(conversation) }
                }
                .onAppear {
                    if conversation.id == viewModel.conversations.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.conversations.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNewMessage) { Image(systemName: "square.and.pencil") }
            }
        }
        .task { await viewModel.loadInitial() }
    }
}

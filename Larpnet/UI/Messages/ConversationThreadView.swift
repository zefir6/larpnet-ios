import SwiftUI

struct ConversationThreadView: View {
    @State private var viewModel: ConversationThreadViewModel

    init(accountId: String, conversationId: String?, appContainer: AppContainer) {
        _viewModel = State(initialValue: ConversationThreadViewModel(
            accountId: accountId, conversationId: conversationId, appContainer: appContainer
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                    }
                }
                .padding()
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            HStack {
                TextField("Message", text: $viewModel.draft)
                    .textFieldStyle(.roundedBorder)
                Button("Send") { Task { await viewModel.send() } }
                    .disabled(viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .overlay {
            if viewModel.isLoading, viewModel.account == nil {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.account?.displayName ?? "Messages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func messageBubble(_ message: DirectMessage) -> some View {
        let isFromOther = message.senderId == viewModel.account?.id
        let bubbleColor: Color = isFromOther ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.2)
        let alignment: HorizontalAlignment = isFromOther ? .leading : .trailing
        let frameAlignment: Alignment = isFromOther ? .leading : .trailing

        VStack(alignment: alignment, spacing: 2) {
            Text(message.text)
                .padding(8)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}

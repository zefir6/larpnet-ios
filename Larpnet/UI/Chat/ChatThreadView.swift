import SwiftUI

struct ChatThreadView: View {
    @State private var viewModel: ChatThreadViewModel
    let onOpenInfo: (String) -> Void

    init(target: ChatThreadTarget, appContainer: AppContainer, onOpenInfo: @escaping (String) -> Void) {
        _viewModel = State(initialValue: ChatThreadViewModel(target: target, appContainer: appContainer))
        self.onOpenInfo = onOpenInfo
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
            if viewModel.isLoading, viewModel.messages.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.roomName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let roomId = viewModel.roomId {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Info") { onOpenInfo(roomId) }
                }
            }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.close() }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let bubbleColor: Color = message.isOwn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15)
        let frameAlignment: Alignment = message.isOwn ? .trailing : .leading

        Text(message.body)
            .padding(8)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}

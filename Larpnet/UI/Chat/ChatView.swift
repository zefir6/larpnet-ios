import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    let onOpenRoom: (ChatRoom) -> Void
    let onNewChat: () -> Void

    init(appContainer: AppContainer, onOpenRoom: @escaping (ChatRoom) -> Void, onNewChat: @escaping () -> Void) {
        _viewModel = State(initialValue: ChatViewModel(appContainer: appContainer))
        self.onOpenRoom = onOpenRoom
        self.onNewChat = onNewChat
    }

    var body: some View {
        List {
            ForEach(viewModel.rooms) { room in
                Button {
                    onOpenRoom(room)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.name).font(.body.weight(.medium))
                        if let preview = room.preview {
                            Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.rooms.isEmpty {
                ProgressView()
            } else if viewModel.rooms.isEmpty {
                Text("No conversations yet").foregroundStyle(.secondary)
            }
        }
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNewChat) { Image(systemName: "square.and.pencil") }
            }
        }
        .task { await viewModel.loadInitial() }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}

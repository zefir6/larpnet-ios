import SwiftUI

struct ChatRoomInfoView: View {
    @State private var viewModel: ChatRoomInfoViewModel
    let onAddMember: () -> Void
    let onLeft: () -> Void

    init(
        roomId: String, appContainer: AppContainer,
        onAddMember: @escaping () -> Void, onLeft: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ChatRoomInfoViewModel(roomId: roomId, appContainer: appContainer))
        self.onAddMember = onAddMember
        self.onLeft = onLeft
    }

    var body: some View {
        List {
            if viewModel.isGroup {
                Section {
                    TextField("Chat name", text: $viewModel.nameInput)
                    Button("Save") { Task { await viewModel.rename() } }
                        .disabled(
                            viewModel.isBusy
                                || viewModel.nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || viewModel.nameInput == viewModel.rawName
                        )
                }
            }
            Section("Participants") {
                ForEach(viewModel.members) { member in
                    HStack {
                        Text(member.displayName)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task { await viewModel.remove(userId: member.userId) }
                        }
                        .disabled(viewModel.isBusy)
                    }
                }
                Button("+ Add person", action: onAddMember)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Section {
                Button("Leave chat", role: .destructive) { Task { await viewModel.leave() } }
                    .disabled(viewModel.isBusy)
            }
        }
        .navigationTitle("Chat info")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading, viewModel.members.isEmpty { ProgressView() }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.didLeave) { _, didLeave in
            if didLeave { onLeft() }
        }
    }
}

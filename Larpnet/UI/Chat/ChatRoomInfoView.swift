import SwiftUI

struct ChatRoomInfoView: View {
    @State private var viewModel: ChatRoomInfoViewModel
    let onAddMember: () -> Void
    let onLeft: () -> Void
    private let appContainer: AppContainer

    init(
        roomId: String, appContainer: AppContainer,
        onAddMember: @escaping () -> Void, onLeft: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ChatRoomInfoViewModel(roomId: roomId, appContainer: appContainer))
        self.onAddMember = onAddMember
        self.onLeft = onLeft
        self.appContainer = appContainer
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
            Section("Notifications") {
                HStack {
                    Text(viewModel.muted ? ChatMute.label(until: viewModel.mutedUntil) : "Notifications on")
                    Spacer()
                    Menu(viewModel.muted ? "Unmute" : "Mute") {
                        ChatMuteMenuItems(
                            muted: viewModel.muted,
                            onMute: { duration in Task { await viewModel.mute(for: duration) } },
                            onUnmute: { Task { await viewModel.unmute() } }
                        )
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            Section("Participants") {
                ForEach(viewModel.members) { member in
                    HStack(spacing: 10) {
                        MatrixAvatarView(
                            avatarUrl: member.avatarUrl, name: member.displayName, size: 36,
                            userId: member.userId, appContainer: appContainer
                        )
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

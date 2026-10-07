import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var pendingLeaveRoom: ChatRoom?
    private let appContainer: AppContainer
    let onOpenRoom: (ChatRoom) -> Void
    let onNewChat: () -> Void

    init(appContainer: AppContainer, onOpenRoom: @escaping (ChatRoom) -> Void, onNewChat: @escaping () -> Void) {
        _viewModel = State(initialValue: ChatViewModel(appContainer: appContainer))
        self.appContainer = appContainer
        self.onOpenRoom = onOpenRoom
        self.onNewChat = onNewChat
    }

    var body: some View {
        List {
            ForEach(viewModel.rooms) { room in
                Button {
                    onOpenRoom(room)
                } label: {
                    ChatRoomRow(room: room, appContainer: appContainer)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { pendingLeaveRoom = room } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .confirmationDialog(
            "Delete this conversation? You'll stop receiving its messages, and starting a new one with the same person begins a fresh conversation.",
            isPresented: Binding(get: { pendingLeaveRoom != nil }, set: { if !$0 { pendingLeaveRoom = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let room = pendingLeaveRoom {
                    Task { await viewModel.leaveRoom(room) }
                }
                pendingLeaveRoom = nil
            }
            Button("Cancel", role: .cancel) { pendingLeaveRoom = nil }
        }
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
                // Deliberately not "square.and.pencil" -- that's the exact icon Home/Local use
                // for "new post" in the same top-right toolbar spot, which is easy to confuse
                // with "new chat" when switching tabs. "plus.bubble" reads unambiguously as
                // starting a new conversation instead.
                Button(action: onNewChat) { Image(systemName: "plus.bubble") }
            }
        }
        .task { await viewModel.loadInitial() }
        .sheet(isPresented: Binding(
            get: { viewModel.recoveryPrompt != nil },
            set: { if !$0 { viewModel.dismissRecoveryPrompt() } }
        )) {
            if let kind = viewModel.recoveryPrompt {
                RecoveryKeyView(
                    mode: kind == .needsSetup ? .setup : .restore,
                    appContainer: appContainer,
                    onDone: { viewModel.dismissRecoveryPrompt() },
                    onSkip: kind != .needsSetup ? { viewModel.dismissRecoveryPrompt() } : nil,
                    legacy: kind == .needsRestoreLegacy
                )
            }
        }
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

/// A room's row in the list -- initials avatar + name/preview + a last-activity timestamp,
/// matching `AccountRow`'s layout (used by the classic Messages list) instead of a bare
/// two-line text row.
private struct ChatRoomRow: View {
    let room: ChatRoom
    let appContainer: AppContainer
    @AppStorage("show_chat_timestamps") private var showTimestamps = true

    private var hasUnread: Bool { room.unreadCount > 0 }

    var body: some View {
        HStack(spacing: 10) {
            MatrixAvatarView(avatarUrl: room.avatarUrl, name: room.name, appContainer: appContainer)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).font(.body.weight(hasUnread ? .semibold : .medium)).lineLimit(1)
                if let preview = room.preview {
                    Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if showTimestamps, let timestamp = room.timestamp {
                    Text(RelativeTime.short(from: timestamp))
                        .font(.caption)
                        .foregroundStyle(hasUnread ? LarpnetTheme.accent : .secondary)
                }
                if hasUnread {
                    Text(room.unreadCount > 99 ? "99+" : "\(room.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(LarpnetTheme.accent, in: Capsule())
                }
            }
        }
    }
}

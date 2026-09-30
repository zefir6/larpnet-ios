import SwiftUI

struct ChatThreadView: View {
    @State private var viewModel: ChatThreadViewModel
    @State private var isAtBottom = true
    @State private var pendingNewMessages = 0
    private let appContainer: AppContainer
    let onOpenInfo: (String) -> Void

    private static let bottomAnchorId = "chat-bottom-anchor"

    init(target: ChatThreadTarget, appContainer: AppContainer, onOpenInfo: @escaping (String) -> Void) {
        _viewModel = State(initialValue: ChatThreadViewModel(target: target, appContainer: appContainer))
        self.appContainer = appContainer
        self.onOpenInfo = onOpenInfo
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(ChatMessageGrouping.build(from: viewModel.messages)) { day in
                            daySeparator(day.date)
                            ForEach(day.clusters) { cluster in
                                clusterView(cluster)
                            }
                        }
                        Color.clear.frame(height: 1)
                            .id(Self.bottomAnchorId)
                            .onAppear { isAtBottom = true; pendingNewMessages = 0 }
                            .onDisappear { isAtBottom = false }
                    }
                    .padding()
                }
                .overlay(alignment: .bottom) {
                    if pendingNewMessages > 0 {
                        Button {
                            withAnimation { scrollProxy.scrollTo(Self.bottomAnchorId, anchor: .bottom) }
                        } label: {
                            Label("\(pendingNewMessages) new", systemImage: "arrow.down")
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(LarpnetTheme.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .padding(.bottom, 8)
                    }
                }
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    guard newCount > oldCount else { return }
                    let justSentOwnMessage = viewModel.messages.last?.isOwn == true
                    if isAtBottom || justSentOwnMessage {
                        withAnimation { scrollProxy.scrollTo(Self.bottomAnchorId, anchor: .bottom) }
                    } else {
                        pendingNewMessages += newCount - oldCount
                    }
                }
                .onAppear {
                    scrollProxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
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
            } else if !viewModel.isLoading, viewModel.messages.isEmpty {
                Text("No messages yet -- say hello").foregroundStyle(.secondary)
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
    private func daySeparator(_ date: Date) -> some View {
        Text(ChatMessageGrouping.dayLabel(for: date))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func clusterView(_ cluster: ChatMessageGrouping.Cluster) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !cluster.isOwn {
                if viewModel.isGroup {
                    MatrixAvatarView(
                        avatarUrl: cluster.senderAvatarUrl, name: cluster.senderDisplayName ?? "?",
                        size: 28, appContainer: appContainer
                    )
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            VStack(alignment: cluster.isOwn ? .trailing : .leading, spacing: 3) {
                if !cluster.isOwn, viewModel.isGroup, let senderDisplayName = cluster.senderDisplayName {
                    Text(senderDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                ForEach(Array(cluster.messages.enumerated()), id: \.element.id) { index, message in
                    messageBubble(message, isOwn: cluster.isOwn, isLastInCluster: index == cluster.messages.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: cluster.isOwn ? .trailing : .leading)
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage, isOwn: Bool, isLastInCluster: Bool) -> some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
            if message.isUndecryptable {
                undecryptableNote
            } else {
                let bubbleColor: Color = isOwn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15)
                Text(message.body)
                    .padding(8)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)
            }
            if isLastInCluster {
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    /// Deliberately not a colored bubble like a real message -- a plain inline note (small,
    /// secondary-colored, lock icon) reads as "this thread has a gap", not as content from the
    /// sender. Shown per-message rather than hiding it outright: a silently missing message
    /// would look like nothing was ever sent, which is worse than an visible, explained gap.
    private var undecryptableNote: some View {
        Label("Message couldn't be decrypted", systemImage: "lock.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

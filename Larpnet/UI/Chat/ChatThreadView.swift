import PhotosUI
import SwiftUI

struct ChatThreadView: View {
    @State private var viewModel: ChatThreadViewModel
    @State private var isAtBottom = true
    @State private var viewportHeight: CGFloat = 0
    @State private var pendingNewMessages = 0
    /// Newest message timestamp already accounted for. "New" means newer than this -- not "the
    /// list got longer": back-pagination prepends up to ~90 older messages and a timeline
    /// reset/clear rebuilds the whole list, and counting those as new made the banner climb
    /// ("25 nowych", growing) with nothing unread (seen on Android, same logic here).
    @State private var newestSeen: Date?
    @State private var pickedPhoto: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase
    private let appContainer: AppContainer
    let onOpenInfo: (String) -> Void

    private static let bottomAnchorId = "chat-bottom-anchor"
    nonisolated private static let scrollSpace = "chat-scroll"

    init(target: ChatThreadTarget, appContainer: AppContainer, onOpenInfo: @escaping (String) -> Void) {
        _viewModel = State(initialValue: ChatThreadViewModel(target: target, appContainer: appContainer))
        self.appContainer = appContainer
        self.onOpenInfo = onOpenInfo
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    // Not lazy: a lazy stack only estimates the height of rows it hasn't built,
                    // so "the bottom" moved as they got measured, and both opening a long
                    // conversation and following new messages landed mid-history (2026-10-28).
                    // The timeline holds at most a few hundred messages; the trade-off is that
                    // every image thumbnail in it starts loading on open (they're cached).
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ChatMessageGrouping.build(from: viewModel.messages)) { day in
                            daySeparator(day.date)
                            ForEach(day.clusters) { cluster in
                                clusterView(cluster)
                            }
                        }
                        // Bottom = this anchor is inside the viewport (with a little slack for
                        // the list's padding). Measured by geometry rather than onAppear/
                        // onDisappear: a lazy stack kept the anchor "appeared" after it scrolled
                        // off screen, so isAtBottom stuck at true -- the "N new" banner never
                        // showed and every incoming message yanked a reader of older history
                        // back to the bottom (seen on the simulator, 2026-10-25).
                        Color.clear.frame(height: 1)
                            .id(Self.bottomAnchorId)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.frame(in: .named(Self.scrollSpace)).minY
                            } action: { anchorY in
                                let atBottom = anchorY <= viewportHeight + 40
                                if atBottom != isAtBottom { isAtBottom = atBottom }
                                if atBottom { pendingNewMessages = 0 }
                            }
                    }
                    .padding()
                }
                .coordinateSpace(.named(Self.scrollSpace))
                // Opens at the newest message and keeps the bottom in place while the content
                // above it changes size (back-pagination, images loading, the keyboard).
                .defaultScrollAnchor(.bottom)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
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
                .onChange(of: viewModel.messages) { oldMessages, messages in
                    guard let newest = messages.map(\.timestamp).max() else { return }
                    let previous = newestSeen
                    newestSeen = max(previous ?? newest, newest)
                    let arrived = previous.map { seen in messages.filter { $0.timestamp > seen } } ?? []
                    let grew = messages.count > oldMessages.count
                    if previous == nil {
                        scrollProxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                    } else if (grew && isAtBottom) || arrived.contains(where: \.isOwn) {
                        withAnimation { scrollProxy.scrollTo(Self.bottomAnchorId, anchor: .bottom) }
                    } else if !isAtBottom {
                        pendingNewMessages += arrived.filter { !$0.isOwn }.count
                    }
                }
                .onAppear {
                    scrollProxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            if let errorMessage = viewModel.errorMessage, !viewModel.failedToLoad {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            // Hidden rather than just disabled when there's no room to send into at all --
            // a visible-but-grayed composer still reads as "this will work once you type
            // something", which isn't true here.
            if !viewModel.failedToLoad {
                HStack {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Image(systemName: "photo")
                            .font(.title3)
                    }
                    .disabled(viewModel.isSending || viewModel.roomId == nil)
                    .accessibilityLabel("Send photo")
                    TextField("Message", text: $viewModel.draft)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") { Task { await viewModel.send() } }
                        .disabled(viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .overlay(alignment: .top) {
                    if viewModel.isSending { ProgressView().controlSize(.small) }
                }
                .onChange(of: pickedPhoto) { _, item in
                    guard let item else { return }
                    pickedPhoto = nil
                    Task { await viewModel.sendImage(item) }
                }
            }
        }
        .overlay {
            if viewModel.isLoading, viewModel.messages.isEmpty {
                ProgressView()
            } else if viewModel.failedToLoad {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Couldn't start this conversation")
                        .font(.headline)
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            } else if !viewModel.isLoading, viewModel.messages.isEmpty {
                Text("No messages yet -- say hello").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(viewModel.roomName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.roomId != nil {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        MatrixAvatarView(
                            avatarUrl: viewModel.avatarUrl, name: viewModel.roomName ?? "Chat", size: 28,
                            userId: viewModel.peerUserId, appContainer: appContainer
                        )
                        Text(viewModel.roomName ?? "Chat").font(.headline).lineLimit(1)
                    }
                }
            }
            if let roomId = viewModel.roomId {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Info") { onOpenInfo(roomId) }
                }
            }
        }
        .task { await viewModel.load() }
        .onAppear { viewModel.setVisible(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in viewModel.setVisible(phase == .active) }
        .onDisappear {
            viewModel.setVisible(false)
            viewModel.close()
        }
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
                        size: 28, userId: cluster.senderId, appContainer: appContainer
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
                if let image = message.image {
                    ChatImageView(image: image, appContainer: appContainer)
                }
                if message.image == nil || !message.body.isEmpty {
                    Text(message.body)
                        .padding(8)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)
                }
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

import SwiftUI

struct FollowedThreadsView: View {
    @State private var viewModel: FollowedThreadsViewModel
    let onOpenThread: (String) -> Void

    init(appContainer: AppContainer, onOpenThread: @escaping (String) -> Void) {
        _viewModel = State(initialValue: FollowedThreadsViewModel(appContainer: appContainer))
        self.onOpenThread = onOpenThread
    }

    var body: some View {
        List {
            ForEach(viewModel.entries) { entry in
                Button {
                    onOpenThread(entry.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        if entry.hasUnread {
                            Circle()
                                .fill(LarpnetTheme.accent)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if let status = entry.status {
                                Text(status.account.displayName.isEmpty ? status.account.username : status.account.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(HTMLParser.plainText(status.content))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else {
                                Text("Thread unavailable")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Unfollow", role: .destructive) { viewModel.unfollow(entry.id) }
                }
            }
            if viewModel.entries.isEmpty, !viewModel.isLoading {
                Text("You're not following any threads yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.entries.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

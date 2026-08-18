import SwiftUI

struct NotificationsView: View {
    @State private var viewModel: NotificationsViewModel
    let onOpenStatus: (String) -> Void
    let onOpenProfile: (String) -> Void

    init(appContainer: AppContainer, onOpenStatus: @escaping (String) -> Void, onOpenProfile: @escaping (String) -> Void) {
        _viewModel = State(initialValue: NotificationsViewModel(appContainer: appContainer))
        self.onOpenStatus = onOpenStatus
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        List {
            ForEach(viewModel.notifications) { notification in
                Button {
                    if let statusId = notification.status?.id {
                        onOpenStatus(statusId)
                    } else {
                        onOpenProfile(notification.account.id)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        AccountRow(account: notification.account, subtitle: description(for: notification))
                        if let status = notification.status {
                            HTMLContentView(html: status.content)
                                .font(.caption)
                                .lineLimit(3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Dismiss", role: .destructive) { viewModel.dismiss(notification) }
                }
                .onAppear {
                    if notification.id == viewModel.notifications.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.notifications.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await viewModel.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear all") { viewModel.clearAll() }
            }
        }
        .task { await viewModel.loadInitial() }
    }

    private func description(for notification: LarpnetNotification) -> String {
        switch notification.type {
        case "follow": return "followed you"
        case "favourite": return "favourited your post"
        case "reblog": return "boosted your post"
        case "mention": return "mentioned you"
        default: return notification.type
        }
    }
}

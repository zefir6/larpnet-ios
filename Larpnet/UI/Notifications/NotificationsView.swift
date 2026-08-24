import SwiftUI

struct NotificationsView: View {
    @State private var viewModel: NotificationsViewModel

    init(appContainer: AppContainer) {
        _viewModel = State(initialValue: NotificationsViewModel(appContainer: appContainer))
    }

    var body: some View {
        List {
            ForEach(viewModel.notifications) { notification in
                // `NavigationLink(value:)`, not a plain `Button` wrapping the row -- a `List`
                // row's own selection gesture unreliably swallows a nested `Button`'s tap (the
                // exact bug already found and fixed this way for the Settings profile row);
                // `NavigationLink` is the mechanism that actually pushes reliably from inside a
                // `List` row.
                NavigationLink(value: route(for: notification)) {
                    VStack(alignment: .leading, spacing: 4) {
                        AccountRow(account: notification.account, subtitle: description(for: notification))
                        if let status = notification.status {
                            Text(preview(for: status))
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
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

    private func route(for notification: LarpnetNotification) -> AppRoute {
        if let statusId = notification.status?.id {
            return .thread(statusId: statusId)
        }
        return .profile(accountId: notification.account.id)
    }

    /// Mirrors Android's `NotificationRow` preview exactly: the CW subject if there is one,
    /// otherwise the post's plain text (HTML stripped) capped at 140 characters -- a single
    /// flat string in a single `Text`, not the full multi-block HTML renderer, so `.lineLimit`
    /// actually limits the whole preview instead of clipping each paragraph independently.
    private func preview(for status: Status) -> String {
        let spoiler = status.spoilerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoiler.isEmpty { return spoiler }
        return String(HTMLParser.plainText(status.content).prefix(140))
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

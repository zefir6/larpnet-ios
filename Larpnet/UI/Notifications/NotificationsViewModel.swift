import Foundation

/// Direct port of Android's `ui/notifications/NotificationsViewModel.kt`: Link-header-paginated
/// notification list, swipe-to-dismiss, clear-all.
@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var notifications: [LarpnetNotification] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var nextMaxId: String?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard notifications.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await appContainer.friendicaAPI().notifications()
            notifications = page.items
            nextMaxId = page.nextMaxId
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func refresh() async {
        do {
            let page = try await appContainer.friendicaAPI().notifications()
            notifications = page.items
            nextMaxId = page.nextMaxId
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadMore() async {
        guard !isLoadingMore, let maxId = nextMaxId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await appContainer.friendicaAPI().notifications(maxId: maxId)
            notifications.append(contentsOf: page.items)
            nextMaxId = page.nextMaxId
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func dismiss(_ notification: LarpnetNotification) {
        notifications.removeAll { $0.id == notification.id }
        Task { try? await appContainer.friendicaAPI().dismissNotification(id: notification.id) }
    }

    func clearAll() {
        notifications = []
        Task { try? await appContainer.friendicaAPI().clearNotifications() }
    }
}

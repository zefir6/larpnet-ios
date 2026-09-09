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

    /// The logged-in user's own account id -- lets the UI tell whether a `favourite`/`reblog`
    /// notification's embedded `status` is genuinely the user's own post (accurate to say
    /// "favourited your post") or someone else's (Friendica's Mastodon-API notification for
    /// "someone liked/reshared your reply" only ever embeds the *thread's* status, which may not
    /// be authored by the user at all -- see `NotificationsView.description(for:)`).
    private(set) var selfAccountId: String?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard notifications.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let selfAccountTask = appContainer.friendicaAPI().verifyCredentials()
            let page = try await appContainer.friendicaAPI().notifications()
            notifications = page.items
            nextMaxId = page.nextMaxId
            selfAccountId = (try? await selfAccountTask)?.id
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

    func acceptFollowRequest(_ notification: LarpnetNotification) {
        notifications.removeAll { $0.id == notification.id }
        let account = notification.account
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            try? await FollowRequestActions.accept(account, api: api)
        }
    }

    func acceptAndFollowBackFollowRequest(_ notification: LarpnetNotification) {
        notifications.removeAll { $0.id == notification.id }
        let account = notification.account
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            try? await FollowRequestActions.acceptAndFollowBack(account, api: api)
        }
    }

    func declineFollowRequest(_ notification: LarpnetNotification) {
        notifications.removeAll { $0.id == notification.id }
        let account = notification.account
        Task {
            guard let api = try? appContainer.friendicaAPI() else { return }
            try? await FollowRequestActions.decline(account, api: api)
        }
    }
}

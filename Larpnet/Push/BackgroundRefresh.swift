@preconcurrency import BackgroundTasks
import Foundation
import UserNotifications

/// Background polling of `GET /api/v1/notifications`, replacing Android's ntfy long-lived-
/// socket relay (see the plan doc's "Push notifications" section for why): a `BGAppRefreshTask`
/// buys no value from holding a relay connection open, so this polls the Mastodon API this app
/// already has a client for instead. `larpnet_push_config`/ntfy integration is intentionally
/// unused in v1.
///
/// iOS gives **no guaranteed interval** for `BGAppRefreshTask` -- this is best-effort, not real
/// push. The only practical way to trigger it during development is the debugger:
/// `e -l objc -- (void)[[BGTaskScheduler sharedScheduler]
/// _simulateLaunchForTaskWithIdentifier:@"pl.larpnet.ios.refresh"]` after `register(...)` has
/// run once.
enum BackgroundRefresh {
    static let taskIdentifier = "pl.larpnet.ios.refresh"
    private static let lastSeenNotificationIdKey = "last_seen_notification_id"

    static func register(appContainer: AppContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handle(task: refreshTask, appContainer: appContainer)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Cancels any pending request -- called when the user turns the push toggle off, so a
    /// stale request doesn't keep firing and silently no-op against `pushEnabled == false`.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func handle(task: BGAppRefreshTask, appContainer: AppContainer) {
        // Reschedule at the *start* of the handler -- a suspended/killed task never
        // reschedules otherwise, silently ending the polling cycle for good.
        schedule()

        let pollTask = Task {
            await poll(appContainer: appContainer)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            pollTask.cancel()
        }
    }

    @MainActor
    static func poll(appContainer: AppContainer) async {
        guard appContainer.tokenStore.isLoggedIn, appContainer.tokenStore.pushEnabled else { return }
        let defaults = UserDefaults.standard
        let sinceId = defaults.string(forKey: lastSeenNotificationIdKey)
        do {
            let api = try appContainer.friendicaAPI()
            let page = try await api.notifications(sinceId: sinceId)
            guard !page.items.isEmpty else { return }
            defaults.set(page.items.first?.id, forKey: lastSeenNotificationIdKey)
            await postLocalNotifications(for: page.items)
        } catch {
            // Best-effort background poll -- no user-visible error surface for a failure here.
        }
    }

    private static func postLocalNotifications(for notifications: [LarpnetNotification]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        if notifications.count > 3 {
            let content = UNMutableNotificationContent()
            content.title = "Larpnet"
            content.body = "\(notifications.count) new notifications"
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return
        }
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.account.displayName.isEmpty
                ? notification.account.username : notification.account.displayName
            content.body = summary(for: notification)
            try? await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: nil))
        }
    }

    private static func summary(for notification: LarpnetNotification) -> String {
        switch notification.type {
        case "follow": return "followed you"
        case "favourite": return "favourited your post"
        case "reblog": return "boosted your post"
        case "mention": return "mentioned you"
        default: return notification.type
        }
    }
}

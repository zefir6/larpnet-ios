import os
import UIKit
import UserNotifications

/// SwiftUI's `App` protocol has no equivalent for the two APNs registration callbacks below --
/// `UIApplicationDelegateAdaptor` (wired in `LarpnetApp`) is the only way to receive a real
/// device token. Everything else this app needs (scene lifecycle, background tasks) already
/// goes through SwiftUI/`BackgroundRefresh` directly, so this stays deliberately minimal.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `LarpnetApp.init()` right after `AppContainer` exists -- by the time
    /// `registerForRemoteNotifications()` actually calls back (asynchronously, after this
    /// delegate's own `didFinishLaunching`), this is always already assigned.
    var appContainer: AppContainer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before launch finishes, or a tap that cold-starts the app is missed.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Foreground pushes: shown as a normal banner, except a chat message for the room that's
    /// already on screen (`ChatBadgeStore.visibleRoomId`).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let roomId = notification.request.content.userInfo["room_id"] as? String
        let visibleRoomId = await MainActor.run { appContainer?.chatBadgeStore.visibleRoomId }
        if let roomId, roomId == visibleRoomId {
            return []
        }
        return [.banner, .list, .sound, .badge]
    }

    /// Tapping a chat notification opens that room (`RootView` presents
    /// `ChatBadgeStore.pendingRoomId`).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let roomId = response.notification.request.content.userInfo["room_id"] as? String, !roomId.isEmpty else { return }
        await MainActor.run { appContainer?.chatBadgeStore.pendingRoomId = roomId }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let appContainer else { return }
        // Cached regardless of pushEnabled/isLoggedIn below -- `SettingsViewModel.togglePush(false)`
        // needs this later to unregister, and there's no other way to get it back on demand.
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        appContainer.tokenStore.apnsDeviceTokenHex = hexToken
        guard appContainer.tokenStore.isLoggedIn, appContainer.tokenStore.pushEnabled else { return }
        Task {
            await appContainer.matrixClientStore.registerPusher(deviceToken: deviceToken)
        }
        // Classic Friendica notifications (likes/comments/follows/DMs) -- a separate
        // registration from the Matrix pusher above, same one APNs device token but a
        // different server-side addon (`larpnet_apns`, not `larpnet_matrix`/Synapse).
        // Best-effort: a failure here (e.g. logged out, transient network error) just means
        // this device stays on `BackgroundRefresh`'s polling fallback for classic
        // notifications until the next successful registration attempt.
        Task {
            if (try? await appContainer.friendicaAPI().registerApnsToken(hexToken)) != nil {
                appContainer.tokenStore.classicApnsRegisteredToken = hexToken
            }
        }
    }

    /// Background wake from a silent/`content-available` remote notification -- lets a Matrix
    /// push catch the sync loop up while suspended, rather than only decrypting one event for
    /// the banner (`NotificationServiceExtension`) and leaving the room list/open chat screen to
    /// notice the backlog whenever the long-poll loop happens to resume on its own. No-op if the
    /// server-sent payload doesn't set `content-available: 1` (iOS never invokes this at all in
    /// that case) or if chat hasn't logged in yet this launch.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let appContainer else {
            completionHandler(.noData)
            return
        }
        Task {
            // `chat_counts` (a read receipt changed the counts, e.g. a chat read on another
            // device): with nothing unread, no sync is needed to know every chat notification
            // can go. Otherwise the catch-up sync's reconcile removes the read rooms' ones.
            if userInfo["type"] as? String == "chat_counts" {
                let unread = userInfo["unread"] as? String ?? "?"
                Logger(subsystem: "pl.larpnet.ios", category: "ChatCounts").info("chat_counts unread=\(unread, privacy: .public)")
                if unread == "0" {
                    await ChatNotifications.removeAllChat()
                }
            }
            await appContainer.matrixClientStore.resyncAndWait()
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "pl.larpnet.ios", category: "ChatPusher")
            .error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
        // Nothing actionable -- the classic Friendica notification path (`BackgroundRefresh`)
        // doesn't depend on this at all, and a retry on the next launch is as good as anything
        // we could do here (typically transient: no network, or push not yet provisioned for
        // this build/profile).
    }
}

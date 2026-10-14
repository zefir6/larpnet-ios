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
            try? await appContainer.friendicaAPI().registerApnsToken(hexToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Nothing actionable -- the classic Friendica notification path (`BackgroundRefresh`)
        // doesn't depend on this at all, and a retry on the next launch is as good as anything
        // we could do here (typically transient: no network, or push not yet provisioned for
        // this build/profile).
    }
}

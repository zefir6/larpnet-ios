import UIKit

/// SwiftUI's `App` protocol has no equivalent for the two APNs registration callbacks below --
/// `UIApplicationDelegateAdaptor` (wired in `LarpnetApp`) is the only way to receive a real
/// device token. Everything else this app needs (scene lifecycle, background tasks) already
/// goes through SwiftUI/`BackgroundRefresh` directly, so this stays deliberately minimal.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `LarpnetApp.init()` right after `AppContainer` exists -- by the time
    /// `registerForRemoteNotifications()` actually calls back (asynchronously, after this
    /// delegate's own `didFinishLaunching`), this is always already assigned.
    var appContainer: AppContainer?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let appContainer else { return }
        // Cached regardless of pushEnabled/isLoggedIn below -- `SettingsViewModel.togglePush(false)`
        // needs this later to unregister, and there's no other way to get it back on demand.
        appContainer.tokenStore.apnsDeviceTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard appContainer.tokenStore.isLoggedIn, appContainer.tokenStore.pushEnabled else { return }
        Task {
            await appContainer.matrixClientStore.registerPusher(deviceToken: deviceToken)
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

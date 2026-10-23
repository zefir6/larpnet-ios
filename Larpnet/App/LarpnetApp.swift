import SwiftUI
import UserNotifications

@main
struct LarpnetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appContainer: AppContainer
    @State private var isLoggedIn: Bool
    @State private var hasAcceptedTerms: Bool

    init() {
        let container = AppContainer()
        _appContainer = State(initialValue: container)
        _isLoggedIn = State(initialValue: container.tokenStore.isLoggedIn)
        _hasAcceptedTerms = State(initialValue: container.tokenStore.hasAcceptedTerms)
        // Registration must happen unconditionally and before the app finishes launching --
        // BGTaskScheduler requires it during `application(_:didFinishLaunchingWithOptions:)`-
        // equivalent startup, regardless of whether the user is logged in yet. Requesting
        // notification *authorization* has to wait until `body` runs (it's async, `init()`
        // isn't), see the `.task` below.
        BackgroundRefresh.register(appContainer: container)
        // `@UIApplicationDelegateAdaptor`'s wrapped value already exists by this point in
        // `init()` (SwiftUI initializes property wrappers before the init body runs) -- so
        // `AppDelegate`'s own `didRegisterForRemoteNotificationsWithDeviceToken` callback,
        // which can fire at any point after `registerForRemoteNotifications()` is called, is
        // guaranteed to see this set.
        appDelegate.appContainer = container
        // Chat badge: Chat tab + app icon, updated after every Matrix sync.
        container.matrixClientStore.onUnreadCountChange = { [weak container] count in
            container?.chatBadgeStore.totalUnreadCount = count
            UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    RootView(appContainer: appContainer, onLoggedOut: { isLoggedIn = false })
                } else if !hasAcceptedTerms {
                    TermsGateView(onAccept: {
                        appContainer.tokenStore.hasAcceptedTerms = true
                        hasAcceptedTerms = true
                    })
                } else {
                    LoginView(appContainer: appContainer, onLoggedIn: {
                        isLoggedIn = true
                        Task {
                            await BackgroundRefresh.requestAuthorizationIfNeededAndSchedule(
                                tokenStore: appContainer.tokenStore
                            )
                        }
                        Task {
                            if let account = try? await appContainer.friendicaAPI().verifyCredentials() {
                                appContainer.currentAccountStore.set(account.id)
                            }
                        }
                        // Same as the relaunch path in `.task` below: chat device + key backup
                        // right away, not on the next launch.
                        Task {
                            try? await appContainer.matrixClientStore.ensureClient()
                            _ = try? await appContainer.matrixClientStore.ensureEncryption()
                        }
                    })
                }
            }
            .environment(\.imageLoader, appContainer.imageLoader)
            .environment(\.font, LarpnetTheme.bodyFont)
            .tint(LarpnetTheme.accent)
            .task {
                // Covers the "already logged in, relaunching the app" path -- fresh logins are
                // handled by `onLoggedIn` above instead, since this only runs once per launch.
                guard appContainer.tokenStore.isLoggedIn else { return }
                await BackgroundRefresh.requestAuthorizationIfNeededAndSchedule(
                    tokenStore: appContainer.tokenStore
                )
                if let account = try? await appContainer.friendicaAPI().verifyCredentials() {
                    appContainer.currentAccountStore.set(account.id)
                }
                // Start chat in the background at launch, not only when the Chat tab first
                // opens, so the unread badge is right from the start. ensureEncryption() too: in
                // standard mode it silently sets up key backup, so room keys this device gets
                // before the user ever opens Chat are backed up for their other devices. Any
                // prompt it returns is ignored here; the Chat tab asks again and shows it.
                try? await appContainer.matrixClientStore.ensureClient()
                _ = try? await appContainer.matrixClientStore.ensureEncryption()
                #if DEBUG
                await DebugChatPush.runIfRequested(appContainer: appContainer)
                #endif
            }
            // Catches up the sync loop on every return to the foreground -- including a tap on
            // a chat notification, which also transitions scene phase to `.active` -- rather
            // than leaving an already-open chat screen or the room list showing whatever the
            // long-poll loop had before iOS suspended this process. Cheap and idempotent (just
            // restarts the existing `syncV2` subscription) if chat is already caught up.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                appContainer.matrixClientStore.resyncNow()
            }
        }
    }
}

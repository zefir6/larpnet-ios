import SwiftUI

@main
struct LarpnetApp: App {
    @State private var appContainer: AppContainer
    @State private var isLoggedIn: Bool

    init() {
        let container = AppContainer()
        _appContainer = State(initialValue: container)
        _isLoggedIn = State(initialValue: container.tokenStore.isLoggedIn)
        // Registration must happen unconditionally and before the app finishes launching --
        // BGTaskScheduler requires it during `application(_:didFinishLaunchingWithOptions:)`-
        // equivalent startup, regardless of whether the user is logged in yet. Requesting
        // notification *authorization* has to wait until `body` runs (it's async, `init()`
        // isn't), see the `.task` below.
        BackgroundRefresh.register(appContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    RootView(appContainer: appContainer, onLoggedOut: { isLoggedIn = false })
                } else {
                    LoginView(appContainer: appContainer, onLoggedIn: {
                        isLoggedIn = true
                        Task {
                            await BackgroundRefresh.requestAuthorizationIfNeededAndSchedule(
                                tokenStore: appContainer.tokenStore
                            )
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
            }
        }
    }
}

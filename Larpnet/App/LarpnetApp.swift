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
        // equivalent startup, regardless of whether the user is logged in yet.
        BackgroundRefresh.register(appContainer: container)
        if container.tokenStore.isLoggedIn, container.tokenStore.pushEnabled {
            BackgroundRefresh.schedule()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    RootView(appContainer: appContainer, onLoggedOut: { isLoggedIn = false })
                } else {
                    LoginView(appContainer: appContainer, onLoggedIn: {
                        isLoggedIn = true
                        if appContainer.tokenStore.pushEnabled { BackgroundRefresh.schedule() }
                    })
                }
            }
            .environment(\.imageLoader, appContainer.imageLoader)
            .environment(\.font, LarpnetTheme.bodyFont)
            .dynamicTypeSize(.medium)
            .tint(LarpnetTheme.accent)
        }
    }
}

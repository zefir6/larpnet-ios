import SwiftUI

/// SwiftUI idiomatic equivalent of Android's `NavGraph.kt`: a `TabView` with the same 5
/// bottom-nav tabs in the same order (Home, Local, Directory, Notifications, Settings), each
/// wrapping its own `NavigationStack` so push navigation stays scoped per tab. Compose is a
/// `.sheet`, not a pushed route (see `AppRoute.swift`).
struct RootView: View {
    let appContainer: AppContainer
    let onLoggedOut: () -> Void

    @State private var homePath: [AppRoute] = []
    @State private var localPath: [AppRoute] = []
    @State private var notificationsPath: [AppRoute] = []
    @State private var directoryPath: [AppRoute] = []
    @State private var settingsPath: [AppRoute] = []
    @State private var composeContext: ComposeContext?

    var body: some View {
        TabView {
            tabStack(path: $homePath) {
                TimelineView(
                    kind: .home, appContainer: appContainer,
                    onOpenThread: { homePath.append(.thread(statusId: $0.id)) },
                    onOpenProfile: { homePath.append(.profile(accountId: $0)) },
                    onReply: { composeContext = ComposeContext(replyToId: $0.id) }
                )
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { homePath.append(.search) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { composeContext = ComposeContext(replyToId: nil) } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
            .tabItem { Label("Home", systemImage: "house") }

            tabStack(path: $localPath) {
                TimelineView(
                    kind: .local, appContainer: appContainer,
                    onOpenThread: { localPath.append(.thread(statusId: $0.id)) },
                    onOpenProfile: { localPath.append(.profile(accountId: $0)) },
                    onReply: { composeContext = ComposeContext(replyToId: $0.id) }
                )
                .navigationTitle("Larpnet")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { composeContext = ComposeContext(replyToId: nil) } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
            .tabItem { Label("Larpnet", systemImage: "person.3") }

            tabStack(path: $directoryPath) {
                DirectoryView(
                    appContainer: appContainer,
                    onOpenProfile: { directoryPath.append(.profile(accountId: $0)) }
                )
                .navigationTitle("Directory")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Directory", systemImage: "person.2") }

            tabStack(path: $notificationsPath) {
                NotificationsView(
                    appContainer: appContainer,
                    onOpenStatus: { notificationsPath.append(.thread(statusId: $0)) },
                    onOpenProfile: { notificationsPath.append(.profile(accountId: $0)) }
                )
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { notificationsPath.append(.messages) } label: {
                            Image(systemName: "envelope")
                        }
                    }
                }
            }
            .tabItem { Label("Notifications", systemImage: "bell") }

            tabStack(path: $settingsPath) {
                SettingsView(appContainer: appContainer, onLoggedOut: onLoggedOut)
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(LarpnetTheme.accent)
        .sheet(item: $composeContext) { context in
            ComposeView(context: context, appContainer: appContainer, onPosted: {})
        }
    }

    @ViewBuilder
    private func tabStack<Content: View>(path: Binding<[AppRoute]>, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: path) {
            content()
                .larpnetNavigationBarStyle()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .thread(let statusId):
                        ThreadView(
                            statusId: statusId, appContainer: appContainer,
                            onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                            onReply: { composeContext = ComposeContext(replyToId: $0.id) }
                        )
                    case .profile(let accountId):
                        ProfileView(
                            accountId: accountId, appContainer: appContainer,
                            onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                            onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                            onEditProfile: { path.wrappedValue.append(.editProfile) }
                        )
                    case .editProfile:
                        EditProfileView(appContainer: appContainer, onSaved: {})
                    case .search:
                        SearchView(
                            appContainer: appContainer,
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) }
                        )
                    case .messages:
                        ConversationsView(
                            appContainer: appContainer,
                            onOpenConversation: { conversation in
                                guard let accountId = conversation.accounts.first?.id else { return }
                                path.wrappedValue.append(.messageThread(accountId: accountId, conversationId: conversation.id))
                            },
                            onNewMessage: { path.wrappedValue.append(.newMessage) }
                        )
                    case .newMessage:
                        SearchView(
                            appContainer: appContainer,
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                            onSelectAccount: { account in
                                path.wrappedValue.removeLast()
                                path.wrappedValue.append(.messageThread(accountId: account.id, conversationId: nil))
                            }
                        )
                    case .messageThread(let accountId, let conversationId):
                        ConversationThreadView(accountId: accountId, conversationId: conversationId, appContainer: appContainer)
                    }
                }
        }
    }
}

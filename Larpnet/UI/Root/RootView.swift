import SwiftUI

/// SwiftUI idiomatic equivalent of Android's `NavGraph.kt`: a `TabView` with the same 5
/// bottom-nav tabs as Android (Home, Local, Directory, Notifications, Settings), each wrapping
/// its own `NavigationStack` so push navigation stays scoped per tab. Compose is a `.sheet`, not
/// a pushed route (see `AppRoute.swift`). Display order is user-configurable (see
/// `BottomNavOrderStore`, `SettingsView`'s "Tab order" section) -- each case's `@State` path
/// binding is fixed to that case, not to a display position, so reordering never scrambles which
/// tab's navigation stack shows where.
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
            ForEach(appContainer.bottomNavOrderStore.order) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.label, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(LarpnetTheme.accent)
        .sheet(item: $composeContext) { context in
            ComposeView(context: context, appContainer: appContainer, onPosted: {})
        }
    }

    /// Each case's content and `@State` path binding stay fixed regardless of where the tab
    /// sits in `bottomNavOrderStore.order` -- reordering must not scramble which tab's push
    /// navigation stack shows where.
    @ViewBuilder
    private func tabContent(for tab: BottomTab) -> some View {
        switch tab {
        case .home:
            tabStack(path: $homePath) {
                TimelineView(
                    kind: .home, appContainer: appContainer,
                    onOpenThread: { homePath.append(.thread(statusId: $0.id)) },
                    onOpenProfile: { homePath.append(.profile(accountId: $0)) },
                    onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                    onOpenHashtag: { homePath.append(.hashtag($0)) }
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
        case .local:
            tabStack(path: $localPath) {
                TimelineView(
                    kind: .local, appContainer: appContainer,
                    onOpenThread: { localPath.append(.thread(statusId: $0.id)) },
                    onOpenProfile: { localPath.append(.profile(accountId: $0)) },
                    onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                    onOpenHashtag: { localPath.append(.hashtag($0)) }
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
        case .directory:
            tabStack(path: $directoryPath) {
                DirectoryView(
                    appContainer: appContainer,
                    onOpenProfile: { directoryPath.append(.profile(accountId: $0)) }
                )
                .navigationTitle("Directory")
                .navigationBarTitleDisplayMode(.inline)
            }
        case .notifications:
            tabStack(path: $notificationsPath) {
                NotificationsView(appContainer: appContainer)
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
        case .settings:
            tabStack(path: $settingsPath) {
                SettingsView(appContainer: appContainer, onLoggedOut: onLoggedOut)
            }
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
                            onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                            onOpenHashtag: { path.wrappedValue.append(.hashtag($0)) }
                        )
                    case .profile(let accountId):
                        ProfileView(
                            accountId: accountId, appContainer: appContainer,
                            onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                            onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                            onEditProfile: { path.wrappedValue.append(.editProfile) },
                            onOpenHashtag: { path.wrappedValue.append(.hashtag($0)) }
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
                    case .blockedAccounts:
                        BlockedAccountsView(appContainer: appContainer)
                    case .hiddenPosts:
                        LocalPostListView(
                            title: "Hidden posts", removeActionLabel: "Unhide",
                            store: appContainer.hiddenPostsStore, appContainer: appContainer,
                            onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) }
                        )
                    case .blockedPosts:
                        LocalPostListView(
                            title: "Blocked posts", removeActionLabel: "Unblock",
                            store: appContainer.blockedPostsStore, appContainer: appContainer,
                            onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) }
                        )
                    case .followedThreads:
                        FollowedThreadsView(
                            appContainer: appContainer,
                            onOpenThread: { path.wrappedValue.append(.thread(statusId: $0)) }
                        )
                    case .hashtag(let tag):
                        TimelineView(
                            kind: .hashtag(tag), appContainer: appContainer,
                            onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                            onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                            onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                            onOpenHashtag: { path.wrappedValue.append(.hashtag($0)) }
                        )
                        .navigationTitle("#\(tag)")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
        }
    }
}

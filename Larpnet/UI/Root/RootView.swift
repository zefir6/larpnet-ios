import SwiftUI

/// SwiftUI idiomatic equivalent of Android's `NavGraph.kt`: a `TabView` whose tabs are whatever
/// `AppDestination`s the user has assigned to the bottom bar (`NavigationLayoutStore`), each
/// wrapping its own `NavigationStack` so push navigation stays scoped per tab. A top-left "more"
/// menu (a `Menu`, this app's first use of one) lists whatever destinations live there instead,
/// pushing the same content onto the *current* tab's stack rather than switching tabs. Compose
/// is a `.sheet`, not a pushed route (see `AppRoute.swift`). Each destination's own `@State`
/// path binding is fixed to that destination, not to a display position, so reordering or
/// reassigning between the bar and the menu never scrambles which stack shows where.
struct RootView: View {
    let appContainer: AppContainer
    let onLoggedOut: () -> Void

    @State private var homePath: [AppRoute] = []
    @State private var localPath: [AppRoute] = []
    @State private var directoryPath: [AppRoute] = []
    @State private var notificationsPath: [AppRoute] = []
    @State private var settingsPath: [AppRoute] = []
    @State private var profilePath: [AppRoute] = []
    @State private var albumsPath: [AppRoute] = []
    @State private var mediaPath: [AppRoute] = []
    @State private var composeContext: ComposeContext?

    var body: some View {
        TabView {
            ForEach(appContainer.navigationLayoutStore.bottomBar) { destination in
                tabContent(for: destination)
                    .tabItem { Label(destination.label, systemImage: destination.systemImage) }
                    .tag(destination)
            }
        }
        .tint(LarpnetTheme.accent)
        .sheet(item: $composeContext) { context in
            ComposeView(context: context, appContainer: appContainer, onPosted: {})
        }
    }

    /// Maps a destination living in the bottom bar to *its own* dedicated path binding -- fixed
    /// per destination regardless of bar position, same rationale as the tab-path binding this
    /// replaces.
    @ViewBuilder
    private func tabContent(for destination: AppDestination) -> some View {
        switch destination {
        case .home: tabStack(path: $homePath) { destinationContent(for: .home, path: $homePath) }
        case .local: tabStack(path: $localPath) { destinationContent(for: .local, path: $localPath) }
        case .directory: tabStack(path: $directoryPath) { destinationContent(for: .directory, path: $directoryPath) }
        case .notifications: tabStack(path: $notificationsPath) { destinationContent(for: .notifications, path: $notificationsPath) }
        case .settings: tabStack(path: $settingsPath) { destinationContent(for: .settings, path: $settingsPath) }
        case .profile: tabStack(path: $profilePath) { destinationContent(for: .profile, path: $profilePath) }
        case .albums: tabStack(path: $albumsPath) { destinationContent(for: .albums, path: $albumsPath) }
        case .media: tabStack(path: $mediaPath) { destinationContent(for: .media, path: $mediaPath) }
        }
    }

    /// The actual screen content for one destination, identical whether it's mounted as a tab
    /// root (via `tabContent(for:)`) or pushed onto the current stack from the top-left menu
    /// (via `AppRoute.destination` below) -- both mount points hand this the stack's own `path`
    /// binding so pushes from within (e.g. opening a thread from Home) land on the right stack
    /// either way. Every case gets the same top-left menu button; per-destination extras
    /// (Home's search, Notifications' messages shortcut) add their own trailing items on top.
    @ViewBuilder
    private func destinationContent(for destination: AppDestination, path: Binding<[AppRoute]>) -> some View {
        Group {
            switch destination {
            case .home:
                TimelineView(
                    kind: .home, appContainer: appContainer,
                    onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                    onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                    onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                    onOpenHashtag: { path.wrappedValue.append(.hashtag($0)) }
                )
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { path.wrappedValue.append(.search) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { composeContext = ComposeContext(replyToId: nil) } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            case .local:
                TimelineView(
                    kind: .local, appContainer: appContainer,
                    onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                    onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                    onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                    onOpenHashtag: { path.wrappedValue.append(.hashtag($0)) }
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
            case .directory:
                DirectoryView(
                    appContainer: appContainer,
                    onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) }
                )
                .navigationTitle("Directory")
                .navigationBarTitleDisplayMode(.inline)
            case .notifications:
                NotificationsView(appContainer: appContainer)
                    .navigationTitle("Notifications")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { path.wrappedValue.append(.messages) } label: {
                                Image(systemName: "envelope")
                            }
                        }
                    }
            case .settings:
                SettingsView(appContainer: appContainer, onLoggedOut: onLoggedOut)
            case .profile:
                ProfileView(
                    accountId: nil, appContainer: appContainer,
                    onOpenThread: { path.wrappedValue.append(.thread(statusId: $0.id)) },
                    onOpenProfile: { path.wrappedValue.append(.profile(accountId: $0)) },
                    onReply: { composeContext = ComposeContext(replyToId: $0.id) },
                    onEditProfile: { path.wrappedValue.append(.editProfile) },
                    onOpenHashtag: { path.wrappedValue.append(.hashtag($0)) },
                    onOpenAlbums: { path.wrappedValue.append(.destination(.albums)) }
                )
            case .albums:
                AlbumsView(
                    appContainer: appContainer,
                    onOpenAlbum: { path.wrappedValue.append(.album($0)) }
                )
            case .media:
                MediaGridView(
                    appContainer: appContainer,
                    onOpenThread: { path.wrappedValue.append(.thread(statusId: $0)) }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(appContainer.navigationLayoutStore.menu) { d in
                        Button(d.label, systemImage: d.systemImage) {
                            path.wrappedValue.append(.destination(d))
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
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
                            onOpenHashtag: { path.wrappedValue.append(.hashtag($0)) },
                            onOpenAlbums: { path.wrappedValue.append(.destination(.albums)) }
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
                    case .albums:
                        AlbumsView(
                            appContainer: appContainer,
                            onOpenAlbum: { path.wrappedValue.append(.album($0)) }
                        )
                    case .album(let name):
                        AlbumDetailView(albumName: name, appContainer: appContainer)
                    case .destination(let d):
                        destinationContent(for: d, path: path)
                    }
                }
        }
    }
}

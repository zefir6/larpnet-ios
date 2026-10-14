import Foundation

/// Every top-level screen the user can reach from the bottom tab bar, the top-left bar, or the
/// bottom-right "More" catch-all -- see `NavigationLayoutStore` for how each destination is
/// assigned to exactly one of the three. Supersedes the old fixed 5-tab `BottomTab`: this app
/// used to have "5 always-shown tabs, reorderable"; now it has N destinations, each living in
/// one of three customizable zones.
enum AppDestination: String, CaseIterable, Identifiable, Codable {
    case home, local, directory, notifications, settings, profile, albums, media, contacts, chat

    /// `.notifications` is deliberately excluded -- it's a fixed top-right icon on every screen
    /// (see `RootView`'s shared toolbar), not something the user places into one of the three
    /// customizable zones, since it's frequent/time-sensitive enough to deserve a guaranteed
    /// spot rather than competing for bar space. The case itself still exists (routing still
    /// needs a destination to push when the bell is tapped, and `destinationContent(for:)`
    /// still needs to render it) -- it's only excluded from `NavigationLayoutStore`'s
    /// partitioning.
    static var customizableCases: [AppDestination] { allCases.filter { $0 != .notifications } }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .local: "Larpnet"
        case .directory: "Directory"
        case .notifications: "Notifications"
        case .settings: "Settings"
        case .profile: "Profile"
        case .albums: "Albums"
        case .media: "Media"
        case .contacts: "Contacts"
        case .chat: "Chat"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .local: "person.3"
        case .directory: "person.2"
        case .notifications: "bell"
        case .settings: "gear"
        case .profile: "person.crop.circle"
        case .albums: "photo.on.rectangle"
        case .media: "photo.stack"
        case .contacts: "person.crop.circle.badge.checkmark"
        case .chat: "bubble.left.and.bubble.right"
        }
    }

    /// The 4 highest-frequency destinations, primary and always visible -- capped at
    /// `NavigationLayoutStore.maximumBottomBarCount`, not 5: the bottom bar plus this app's own
    /// fixed "More" tab are real `TabView` tabs, and a 5-bar/6-total split trips UIKit's
    /// automatic tab-overflow collapse (see that constant's doc comment). Notifications isn't
    /// here at all -- it's the fixed top-right icon (see `customizableCases`), not a bar slot.
    static let defaultBottomBar: [AppDestination] = [.local, .home, .chat, .directory]
    /// Deliberately small -- real screen space next to the nav title. Profile lives here rather
    /// than in the bottom bar purely because the bar is capped at 4 (see above), not because
    /// it's lower-frequency than Settings.
    static let defaultTopBar: [AppDestination] = [.profile, .settings]
    /// Everything else, reached via the bottom-right "More" tab.
    static let defaultMore: [AppDestination] = [.albums, .media, .contacts]
}

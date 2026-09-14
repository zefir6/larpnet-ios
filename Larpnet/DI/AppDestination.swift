import Foundation

/// Every top-level screen the user can reach either from the bottom tab bar or the top-left
/// menu -- see `NavigationLayoutStore` for how each destination is assigned to exactly one of
/// the two. Supersedes the old fixed 5-tab `BottomTab`: this app used to have "5 always-shown
/// tabs, reorderable"; now it has N destinations, each living in the bar or the menu.
enum AppDestination: String, CaseIterable, Identifiable, Codable {
    case home, local, directory, notifications, settings, profile, albums, media, contacts

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
        }
    }

    /// Matches the user's stated example: Profile takes Settings' old spot in the bar, and
    /// Settings moves into the menu alongside the two new photo-browsing destinations.
    static let defaultBottomBar: [AppDestination] = [.local, .home, .directory, .notifications, .profile]
    static let defaultMenu: [AppDestination] = [.settings, .albums, .media, .contacts]
}

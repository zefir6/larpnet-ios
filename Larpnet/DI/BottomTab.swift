import Foundation

/// Direct port of Android's `ui/nav/BottomTab.kt`: the app's 5 bottom-nav tabs as a reorderable
/// enum, `label`/`systemImage` mirroring `RootView.swift`'s previously-hardcoded `.tabItem`
/// values exactly.
enum BottomTab: String, CaseIterable, Identifiable, Codable {
    case home, local, directory, notifications, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .local: "Larpnet"
        case .directory: "Directory"
        case .notifications: "Notifications"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .local: "person.3"
        case .directory: "person.2"
        case .notifications: "bell"
        case .settings: "gear"
        }
    }

    /// Local/"Larpnet" feed leads, matching Android's default (`ui/nav/BottomTab.kt`'s
    /// `defaultBottomTabOrder`) -- the namesake feed gets top billing.
    static let defaultOrder: [BottomTab] = [.local, .home, .directory, .notifications, .settings]
}

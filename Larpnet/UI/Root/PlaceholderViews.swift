import SwiftUI

/// Stand-ins for screens not yet ported (see the plan doc's phase list) -- kept in one file so
/// it's obvious at a glance what's still outstanding. Each is replaced by its real
/// implementation in its own phase without touching the navigation plumbing wired up here.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Not built yet."))
    }
}

struct DirectoryPlaceholderView: View {
    var body: some View { ComingSoonView(title: "Directory") }
}

struct NotificationsPlaceholderView: View {
    var body: some View { ComingSoonView(title: "Notifications") }
}

struct ThreadPlaceholderView: View {
    let statusId: String
    var body: some View { ComingSoonView(title: "Thread \(statusId)") }
}

struct ProfilePlaceholderView: View {
    let accountId: String?
    var body: some View { ComingSoonView(title: accountId ?? "Profile") }
}

struct SearchPlaceholderView: View {
    var body: some View { ComingSoonView(title: "Search") }
}

struct EditProfilePlaceholderView: View {
    var body: some View { ComingSoonView(title: "Edit Profile") }
}

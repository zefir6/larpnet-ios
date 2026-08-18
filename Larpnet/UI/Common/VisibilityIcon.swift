import SwiftUI

/// Icon for a status's `visibility` field. Direct port of Android's
/// `ui/common/VisibilityIcon.kt`. Only "public" | "private" | "unlisted" ever actually appear
/// (see `Status`'s doc comment -- "direct" is never emitted by this server), but "direct" is
/// still handled defensively since it's part of the Mastodon API's visibility enum in general.
struct VisibilityIcon: View {
    let visibility: String

    private var systemName: String {
        switch visibility {
        case "public": return "globe"
        case "unlisted": return "lock.open"
        case "private": return "lock"
        case "direct": return "envelope"
        default: return "globe"
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

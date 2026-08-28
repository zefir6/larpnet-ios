import SwiftUI

/// Icon for a status's `visibility` field. Direct port of Android's
/// `ui/common/VisibilityIcon.kt`. "public" | "private" | "unlisted" | "local" actually appear
/// (see `Status`'s doc comment -- "direct" is never emitted by this server), but "direct" is
/// still handled defensively since it's part of the Mastodon API's visibility enum in general.
/// "local" is Friendica-larpnet's own server-only level (`Item::SERVER_ONLY`) -- visible to all
/// logged-in users on this server, never federated to other instances.
struct VisibilityIcon: View {
    let visibility: String

    /// Shared with `ComposeView`'s visibility picker, so the symbol shown while choosing a
    /// visibility matches the one shown on the resulting post everywhere else.
    static func systemName(for visibility: String) -> String {
        switch visibility {
        case "public": return "globe"
        case "unlisted": return "lock.open"
        case "private": return "lock"
        case "direct": return "envelope"
        case "local": return "server.rack"
        default: return "globe"
        }
    }

    var body: some View {
        Image(systemName: Self.systemName(for: visibility))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

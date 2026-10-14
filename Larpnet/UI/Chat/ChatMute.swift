import SwiftUI

/// Mute durations offered everywhere (same list as the web client's `MUTE_OPTIONS` and
/// Android's `muteDurations`); nil = until turned back on.
enum ChatMute {
    static let durations: [(label: String, duration: TimeInterval?)] = [
        ("1 hour", 3600),
        ("8 hours", 8 * 3600),
        ("24 hours", 24 * 3600),
        ("1 week", 7 * 24 * 3600),
        ("Until I turn it back on", nil),
    ]

    /// "Muted" / "Muted until <date time>".
    static func label(until: Date?) -> String {
        guard let until else { return "Muted" }
        return "Muted until \(until.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// Mute/unmute menu items, for a context menu or a `Menu`.
struct ChatMuteMenuItems: View {
    let muted: Bool
    let onMute: (TimeInterval?) -> Void
    let onUnmute: () -> Void

    var body: some View {
        if muted {
            Button("Unmute", systemImage: "bell") { onUnmute() }
        } else {
            ForEach(ChatMute.durations, id: \.label) { option in
                Button(option.label) { onMute(option.duration) }
            }
        }
    }
}

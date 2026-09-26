import SwiftUI

/// A single-letter circular avatar for a chat room/contact -- used wherever there is no real
/// Matrix room avatar to load (this app doesn't resolve `mxc://` room avatars yet, see
/// `ChatRoom` -- unlike `AccountRow`'s `RemoteImage`, which loads a real Mastodon account
/// avatar URL). The background color is a deterministic hash of `name` rather than one fixed
/// color, so a room list full of these still reads as visually distinct rows at a glance, same
/// as Element/most other chat apps do for text-only avatars -- the counterpart of Android's
/// `ui/common/InitialsAvatar.kt`.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 44

    /// A fixed palette (not an arbitrary HSV hash) so every color stays legible with white text
    /// and visually fits the app's own purple-accented theme rather than clashing with it --
    /// same palette as the Android counterpart, for cross-platform consistency.
    private static let palette: [Color] = [
        LarpnetTheme.navBar,
        LarpnetTheme.accent,
        Color(hex: 0x3C7A89), // teal
        Color(hex: 0x89623C), // brown
        Color(hex: 0x4B8A3C), // green
        Color(hex: 0x8A3C4B), // maroon
        Color(hex: 0x3C5A8A), // blue
        Color(hex: 0x8A7A3C), // olive
    ]

    private var letter: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    private var background: Color {
        // `.magnitude` (not `abs()`) since `abs(Int.min)` traps -- astronomically unlikely for
        // a room name's hashValue to land exactly there, but there's no reason to carry a trap
        // risk at all when the unsigned magnitude does the same job safely.
        let index = Int(name.hashValue.magnitude % UInt(Self.palette.count))
        return Self.palette[index]
    }

    var body: some View {
        Circle()
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                Text(letter)
                    .font(.system(size: size / 2.2, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

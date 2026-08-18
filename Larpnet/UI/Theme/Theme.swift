import SwiftUI

/// Colors and type lifted directly from the production web theme (`friendica-larpnet`'s
/// `view/theme/larpnet_notifications`, fetched live from `larpnet.pl`'s computed
/// `style.pcss`), not guessed -- this is what makes the app actually look like the site
/// rather than a generic purple reskin:
///   - accent / link color:      #a54bad  (link color, hover #94439b)
///   - top bar / prominent:      #833c89  (`#topbar-first`, `.btn-primary` background)
///   - page background:         #ededed  (`body { background-color }`)
///   - card/panel background:   #ffffff  (`.panel { background-color }`, 4px radius, subtle shadow)
///   - body text:                #444444 (`body { color }`)
///   - base font: "Open Sans" (bundled -- `Resources/Fonts/`), at a base size a little under
///     iOS's default to match the web theme's Bootstrap-3-derived 14px base (smaller than a
///     browser's 16px default, same relative step taken here off iOS's 17pt body default).
enum LarpnetTheme {
    static let accent = Color(hex: 0xA54BAD)
    static let accentHover = Color(hex: 0x94439B)
    static let navBar = Color(hex: 0x833C89)
    static let pageBackground = Color(hex: 0xEDEDED)
    static let cardBackground = Color.white
    static let bodyText = Color(hex: 0x444444)

    enum FontName {
        static let regular = "OpenSans"
        static let semibold = "OpenSans-Semibold"
        static let bold = "OpenSans-Bold"
        static let italic = "OpenSans-Italic"
    }

    /// The app-wide default `Text` font (see `LarpnetApp`'s `.environment(\.font, ...)`).
    /// Explicit `.font(.headline)`/`.caption`/etc. calls elsewhere override this locally, same
    /// as any SwiftUI environment value -- `.dynamicTypeSize(.medium)` (one notch below the
    /// system default `.large`) is what makes *those* slightly smaller too, uniformly, without
    /// having to touch every call site.
    static let bodyFont = Font.custom(FontName.regular, size: 15)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Applies the web theme's deep-purple top bar with white title/icons to a `NavigationStack`'s
/// bars -- the single most recognizable piece of the site's brand identity.
struct LarpnetNavigationBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(LarpnetTheme.navBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func larpnetNavigationBarStyle() -> some View {
        modifier(LarpnetNavigationBarStyle())
    }

    /// Wraps content in a white, rounded, subtly-shadowed card -- matching the web theme's
    /// `.panel` component (posts, profile headers, etc. are all `.panel`s there).
    func larpnetCard() -> some View {
        self
            .background(LarpnetTheme.cardBackground, in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

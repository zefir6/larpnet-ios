import SwiftUI
import UIKit

/// Colors and type lifted directly from the production web theme (`friendica-larpnet`'s
/// `view/theme/larpnet_notifications`, fetched live from `larpnet.pl`'s computed
/// `style.pcss`), not guessed -- this is what makes the app actually look like the site
/// rather than a generic purple reskin:
///   - accent / link color:      #a54bad  (link color, hover #94439b)
///   - top bar / prominent:      #833c89  (`#topbar-first`, `.btn-primary` background)
///   - page background:         #ededed  (`body { background-color }`)
///   - card/panel background:   #ffffff  (`.panel { background-color }`, 4px radius, subtle shadow)
///   - body text:                #444444 (`body { color }`)
///   - base font: "Open Sans" (bundled -- `Resources/Fonts/`), a shade under iOS's 17pt body
///     default -- full 17pt read too large on-device, but the web theme's 14px Bootstrap-3 base
///     was too small, so this splits the difference rather than matching either exactly.
///
/// `pageBackground`/`cardBackground` are dynamic (light/dark variants) -- every screen's actual
/// text relies on SwiftUI's normal adaptive colors (`.secondary`, default label, etc.), which
/// correctly turn white in dark mode. Leaving these two backgrounds hardcoded to their
/// light-mode web values would put that adaptive white text on a background that never got the
/// memo, which is exactly the white-on-white bug this fixes. `accent`/`navBar` stay constant
/// across modes deliberately -- one brand purple with enough contrast against both a light and
/// a near-black surface, same as most apps' single accent color.
enum LarpnetTheme {
    static let accent = Color(hex: 0xA54BAD)
    static let accentHover = Color(hex: 0x94439B)
    static let navBar = Color(hex: 0x833C89)
    static let pageBackground = Color(light: 0xEDEDED, dark: 0x000000)
    static let cardBackground = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Tint for the focused post in `ThreadView`'s shared panel, so it visually stands out from
    /// its ancestors/replies. The dark value is a desaturated, low-luminance take on the light
    /// wash (`0xF3E1F5`) rather than that same hex reused verbatim -- see this enum's own doc
    /// comment above for why a flat hex would put dark-mode's adaptive white text on a
    /// still-light background.
    static let highlight = Color(light: 0xF3E1F5, dark: 0x2C2030)

    enum FontName {
        static let regular = "OpenSans"
        static let semibold = "OpenSans-Semibold"
        static let bold = "OpenSans-Bold"
        static let italic = "OpenSans-Italic"
    }

    /// The app-wide default `Text` font (see `LarpnetApp`'s `.environment(\.font, ...)`).
    /// Explicit `.font(.headline)`/`.caption`/etc. calls elsewhere override this locally.
    static let bodyFont = Font.custom(FontName.regular, size: 16)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that switches between `light`/`dark` hex values based on the current trait
    /// environment (system Light/Dark Mode, or a view's own `.preferredColorScheme` override).
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
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

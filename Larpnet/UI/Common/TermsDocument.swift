import SwiftUI

/// Parsed form of `Resources/Terms/terms.md`/`terms.pl.md` -- a deliberately tiny markdown
/// subset (a leading `# ` title, `## ` section headings, and blank-line-separated paragraphs),
/// not a general renderer: just enough structure for whoever edits those files to add/reorder/
/// reword sections without needing to touch any Swift. Shared by `TermsGateView` (pre-login,
/// with an Accept button) and `TermsOfUseView` (Settings, read-only) so the wording only lives
/// in one place.
struct TermsDocument {
    let title: String
    let blocks: [Block]

    enum Block {
        case heading(String)
        case paragraph(String)
    }

    static let fallback = TermsDocument(
        title: "Terms of Use",
        blocks: [.paragraph(
            "Larpnet has zero tolerance for objectionable content or abusive users. Report or block from any post or profile's menu."
        )]
    )

    /// `Locale.current` is scoped to the app's *declared* localizations (`CFBundleLocalizations`
    /// in Info.plist) -- since this app declares none (English-only, no `.lproj` folders), it
    /// resolves to the development region regardless of the device's actual language, even when
    /// launched with `-AppleLanguages "(pl)"`. Confirmed live: it stayed "en" on a simulator
    /// whose system language and `Locale.preferredLanguages` were both genuinely Polish.
    /// `Locale.preferredLanguages` reads the device's raw language-preference list instead,
    /// unaffected by what this app happens to declare -- the right signal here, since this is
    /// our own resource-file selection, not Apple's actual localization system.
    static var isPolishPreferred: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") ?? false
    }

    /// Picks `terms.pl.md` for a Polish device language, `terms.md` otherwise. Both are bundled
    /// resources (see `Resources/Terms/`, added to the target the same way the `.ttf` fonts are
    /// -- no special XcodeGen config needed).
    static func loadForCurrentLocale() -> TermsDocument {
        let filename = isPolishPreferred ? "terms.pl" : "terms"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .fallback
        }
        return parse(text)
    }

    static func parse(_ text: String) -> TermsDocument {
        var title = fallback.title
        var blocks: [Block] = []
        for rawBlock in text.components(separatedBy: "\n\n") {
            let trimmed = rawBlock.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("# ") {
                title = String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.heading(String(trimmed.dropFirst(3))))
            } else {
                blocks.append(.paragraph(trimmed.components(separatedBy: "\n").joined(separator: " ")))
            }
        }
        return blocks.isEmpty ? .fallback : TermsDocument(title: title, blocks: blocks)
    }
}

/// Renders a document's `blocks` (not its `title` -- callers place that however fits their own
/// screen chrome: `TermsGateView` as a large in-body heading, `TermsOfUseView` as the
/// navigation title).
struct TermsBlocksView: View {
    let blocks: [TermsDocument.Block]

    var body: some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .heading(let text):
                Text(text)
                    .font(.custom(LarpnetTheme.FontName.semibold, size: 17))
                    .padding(.top, 4)
            case .paragraph(let text):
                Text(text)
            }
        }
    }
}

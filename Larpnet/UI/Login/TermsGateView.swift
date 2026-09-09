import SwiftUI

/// Shown before every login (not just the device's first ever one), so the terms are presented
/// before each registration/login -- Apple guideline 1.2 requires this text itself (not a
/// linked-out page) to make clear there's no tolerance for objectionable content or abusive
/// users. Acceptance is recorded in `TokenStore.hasAcceptedTerms`, which `clear()` resets on
/// logout (see that property's doc comment), so a fresh login -- same account or a different
/// one -- goes through this screen again. Also reachable read-only afterwards via
/// `TermsOfUseView`, from Settings' "Safety" section.
///
/// The document itself (`TermsDocument`, `TermsBlocksView`) lives in `UI/Common` -- the wording
/// lives in `Resources/Terms/terms.md`/`terms.pl.md`, not in any Swift file, editable and
/// re-buildable without touching code, by design.
struct TermsGateView: View {
    let onAccept: () -> Void

    private var document: TermsDocument { TermsDocument.loadForCurrentLocale() }

    private var continueButtonTitle: String {
        TermsDocument.isPolishPreferred ? "Akceptuję i kontynuuję" : "Agree and Continue"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(document.title)
                        .font(.custom(LarpnetTheme.FontName.bold, size: 28))
                        .foregroundStyle(LarpnetTheme.navBar)
                        .padding(.bottom, 4)

                    TermsBlocksView(blocks: document.blocks)
                }
                .padding()
            }
            Divider()
            Button(continueButtonTitle, action: onAccept)
                .buttonStyle(.borderedProminent)
                .tint(LarpnetTheme.navBar)
                .padding()
        }
        .background(LarpnetTheme.pageBackground)
    }
}

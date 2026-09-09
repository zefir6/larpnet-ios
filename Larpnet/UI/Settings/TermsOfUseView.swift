import SwiftUI

/// Read-only view of the same terms `TermsGateView` presents before login (see that file) --
/// reachable afterwards from Settings' "Safety" section for anyone who wants to re-read them.
/// No Accept button here; this is just for reference.
struct TermsOfUseView: View {
    private var document: TermsDocument { TermsDocument.loadForCurrentLocale() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TermsBlocksView(blocks: document.blocks)
            }
            .padding()
        }
        .background(LarpnetTheme.pageBackground)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI
import UIKit

/// Copies a profile link to the pasteboard and flips to a checkmark for 1.5 s -- the native
/// counterpart of the web's "Kopiuj link" buttons (profile card, chat info panel, member rows).
struct CopyLinkButton: View {
    let url: URL
    var title: String = "Copy profile link"
    /// Icon only (member rows); otherwise a labelled button.
    var compact = false
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.url = url
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            if compact {
                Image(systemName: copied ? "checkmark" : "link")
            } else {
                Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "link")
            }
        }
        .accessibilityLabel(copied ? "Copied" : title)
    }
}

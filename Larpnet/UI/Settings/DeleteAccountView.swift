import SwiftUI

/// Friendica has no REST API for self-deletion, so this links out to the server's own web
/// removal form (`SettingsViewModel.accountRemovalURL`) rather than deleting anything in-app --
/// per Apple's guideline 5.1.1(v), only offering deactivation is insufficient, but a link
/// directly to the completion page is an accepted alternative to a fully native flow.
struct DeleteAccountView: View {
    let appContainer: AppContainer
    @State private var confirmed = false

    private var accountRemovalURL: URL? {
        guard let base = appContainer.tokenStore.instanceBaseURL else { return nil }
        return URL(string: "settings/removeme", relativeTo: URL(string: base))
    }

    var body: some View {
        List {
            Section {
                Text("Deleting your account permanently removes your profile, posts, and messages from the Larpnet server. This cannot be undone.")
            }

            Section {
                Toggle(isOn: $confirmed) {
                    Text("I understand this is permanent")
                }
            }

            if let accountRemovalURL {
                Section {
                    Link(destination: accountRemovalURL) {
                        Text("Continue to account deletion")
                    }
                    .disabled(!confirmed)
                } footer: {
                    Text("Opens the Larpnet server's account removal page, where you'll confirm your password to finish deleting your account.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

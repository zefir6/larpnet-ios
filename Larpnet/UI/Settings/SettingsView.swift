import SwiftUI

/// Direct port of Android's `ui/settings/SettingsScreen.kt`: profile summary, privacy switches
/// (locked/discoverable/bot), push toggle (drives `BackgroundRefresh` instead of Android's
/// `NtfyListenerService` -- see that file's doc comment), "open web settings" fallback for
/// anything with no API route, logout.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var serverInput: String
    @State private var showingChangeServerConfirmation = false
    let onLoggedOut: () -> Void
    private let appContainer: AppContainer

    init(appContainer: AppContainer, onLoggedOut: @escaping () -> Void) {
        self.appContainer = appContainer
        _viewModel = State(initialValue: SettingsViewModel(appContainer: appContainer))
        _serverInput = State(initialValue: appContainer.tokenStore.preferredInstance)
        self.onLoggedOut = onLoggedOut
    }

    /// The domain actually authenticated against right now (falls back to the not-yet-logged-in
    /// preferred instance, though this view is only ever shown while logged in).
    private var currentInstanceHost: String {
        appContainer.tokenStore.instanceBaseURL.flatMap { URL(string: $0)?.host }
            ?? appContainer.tokenStore.preferredInstance
    }

    private var trimmedServerInput: String {
        serverInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            if let account = viewModel.account {
                // `NavigationLink(value:)`, not a plain `Button` -- a `List` row's own
                // selection gesture reliably swallows a nested `Button`'s tap (confirmed live:
                // the button's action never fired, with no error and no fallback behavior,
                // even though XCUITest could target and synthesize the tap correctly).
                // `NavigationLink` is what `List` rows are actually built to host, and it
                // hooks directly into the `navigationDestination(for: AppRoute.self)` already
                // registered by `RootView`'s `tabStack` -- it also draws its own disclosure
                // chevron, so the manual one this used to add is gone.
                Section {
                    NavigationLink(value: AppRoute.profile(accountId: nil)) {
                        AccountRow(account: account)
                    }
                }
            }

            Section("Notifications") {
                Toggle("Push notifications", isOn: Binding(
                    get: { viewModel.pushEnabled },
                    set: { viewModel.togglePush($0) }
                ))
                Text("Best-effort background refresh -- iOS does not guarantee an interval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Manually approve followers", isOn: $viewModel.locked)
                Toggle("Discoverable", isOn: $viewModel.discoverable)
                Toggle("Bot account", isOn: $viewModel.bot)
            }
            .onChange(of: viewModel.locked) { _, _ in viewModel.savePrivacy() }
            .onChange(of: viewModel.discoverable) { _, _ in viewModel.savePrivacy() }
            .onChange(of: viewModel.bot) { _, _ in viewModel.savePrivacy() }

            Section {
                TextField("Instance (e.g. larpnet.pl)", text: $serverInput)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Change Server") {
                    showingChangeServerConfirmation = true
                }
                .disabled(trimmedServerInput.isEmpty || trimmedServerInput == currentInstanceHost)
            } header: {
                Text("Server")
            } footer: {
                Text("Currently connected to \(currentInstanceHost). Changing this logs you out -- you'll sign back in against the new server.")
            }

            if let webSettingsURL = viewModel.webSettingsURL {
                Section {
                    Link("Open web settings", destination: webSettingsURL)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button("Log out", role: .destructive) {
                    appContainer.tokenStore.clear()
                    onLoggedOut()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Change Server?", isPresented: $showingChangeServerConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Change & Log Out", role: .destructive) {
                appContainer.tokenStore.preferredInstance = trimmedServerInput
                appContainer.tokenStore.clear()
                onLoggedOut()
            }
        } message: {
            Text("You'll be logged out of \(currentInstanceHost) and returned to the login screen to sign in to \(trimmedServerInput).")
        }
    }
}

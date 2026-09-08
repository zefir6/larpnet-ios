import SwiftUI

/// Direct port of Android's `ui/settings/SettingsScreen.kt`: profile summary, privacy switches
/// (locked/discoverable/bot), push toggle (drives `BackgroundRefresh` instead of Android's
/// `NtfyListenerService` -- see that file's doc comment), "open web settings" fallback for
/// anything with no API route, an abuse-reporting/child-safety-standards "Safety" section, and
/// logout.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    let onLoggedOut: () -> Void
    private let appContainer: AppContainer

    init(appContainer: AppContainer, onLoggedOut: @escaping () -> Void) {
        self.appContainer = appContainer
        _viewModel = State(initialValue: SettingsViewModel(appContainer: appContainer))
        self.onLoggedOut = onLoggedOut
    }

    /// The domain actually authenticated against right now (falls back to the not-yet-logged-in
    /// preferred instance, though this view is only ever shown while logged in).
    private var currentInstanceHost: String {
        appContainer.tokenStore.instanceBaseURL.flatMap { URL(string: $0)?.host }
            ?? appContainer.tokenStore.preferredInstance
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

            Section {
                ForEach(appContainer.navigationLayoutStore.bottomBar) { destination in
                    Label(destination.label, systemImage: destination.systemImage)
                        .swipeActions(edge: .trailing) {
                            if appContainer.navigationLayoutStore.bottomBar.count > NavigationLayoutStore.minimumBottomBarCount {
                                Button("Move to Menu") {
                                    appContainer.navigationLayoutStore.moveToMenu(destination)
                                }
                                .tint(.blue)
                            }
                        }
                }
                .onMove { indices, newOffset in
                    var order = appContainer.navigationLayoutStore.bottomBar
                    order.move(fromOffsets: indices, toOffset: newOffset)
                    appContainer.navigationLayoutStore.setBottomBar(order)
                }
            } header: {
                Text("Bottom bar")
            } footer: {
                Text("At least \(NavigationLayoutStore.minimumBottomBarCount) must stay in the bottom bar.")
            }

            Section("Top-left menu") {
                ForEach(appContainer.navigationLayoutStore.menu) { destination in
                    Label(destination.label, systemImage: destination.systemImage)
                        .swipeActions(edge: .trailing) {
                            Button("Move to Bottom Bar") {
                                appContainer.navigationLayoutStore.moveToBottomBar(destination)
                            }
                            .tint(.blue)
                        }
                }
                .onMove { indices, newOffset in
                    var order = appContainer.navigationLayoutStore.menu
                    order.move(fromOffsets: indices, toOffset: newOffset)
                    appContainer.navigationLayoutStore.setMenu(order)
                }
            }

            Section("Privacy") {
                Toggle("Manually approve followers", isOn: $viewModel.locked)
                Toggle("Discoverable", isOn: $viewModel.discoverable)
                Toggle("Bot account", isOn: $viewModel.bot)
            }
            .onChange(of: viewModel.locked) { _, _ in viewModel.savePrivacy() }
            .onChange(of: viewModel.discoverable) { _, _ in viewModel.savePrivacy() }
            .onChange(of: viewModel.bot) { _, _ in viewModel.savePrivacy() }

            Section("Moderation") {
                NavigationLink(value: AppRoute.blockedAccounts) {
                    Label("Blocked users", systemImage: "person.crop.circle.badge.xmark")
                }
                NavigationLink(value: AppRoute.hiddenPosts) {
                    Label("Hidden posts", systemImage: "eye.slash")
                }
                NavigationLink(value: AppRoute.blockedPosts) {
                    Label("Blocked posts", systemImage: "hand.raised")
                }
            }

            Section("Following") {
                NavigationLink(value: AppRoute.followedThreads) {
                    Label("Followed threads", systemImage: "bookmark")
                }
            }

            // Read-only -- the server is changed via the iOS Settings app's own "Larpnet"
            // page (`Settings.bundle/Root.plist`), not here. An OAuth session is tied to one
            // instance, so editing it in-app would need to force an immediate logout right in
            // the middle of Settings; parking it at the OS level instead makes it a "next
            // login" preference, with no in-flow disruption.
            Section {
                LabeledContent("Server", value: currentInstanceHost)
            } footer: {
                Text("Change this in iOS Settings \u{2192} Larpnet \u{2192} Server. Takes effect the next time you log in.")
            }

            if let webSettingsURL = viewModel.webSettingsURL {
                Section {
                    Link("Open web settings", destination: webSettingsURL)
                }
            }

            Section("Safety") {
                Link("Report abuse", destination: viewModel.reportAbuseURL)
                Link("Child safety standards", destination: viewModel.childSafetyStandardsURL)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .task { await viewModel.load() }
    }
}

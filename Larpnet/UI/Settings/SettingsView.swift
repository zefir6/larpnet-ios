import SwiftUI

/// Direct port of Android's `ui/settings/SettingsScreen.kt`: profile summary, privacy switches
/// (locked/discoverable/bot), push toggle (drives `BackgroundRefresh` instead of Android's
/// `NtfyListenerService` -- see that file's doc comment), "open web settings" fallback for
/// anything with no API route, an abuse-reporting/child-safety-standards "Safety" section, and
/// logout.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @AppStorage("show_chat_timestamps") private var showChatTimestamps = true
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
                    navigationRow(destination, in: .bottomBar)
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

            Section("Top-left bar") {
                ForEach(appContainer.navigationLayoutStore.topBar) { destination in
                    navigationRow(destination, in: .topBar)
                }
                .onMove { indices, newOffset in
                    var order = appContainer.navigationLayoutStore.topBar
                    order.move(fromOffsets: indices, toOffset: newOffset)
                    appContainer.navigationLayoutStore.setTopBar(order)
                }
            }

            Section("More") {
                ForEach(appContainer.navigationLayoutStore.more) { destination in
                    navigationRow(destination, in: .more)
                }
                .onMove { indices, newOffset in
                    var order = appContainer.navigationLayoutStore.more
                    order.move(fromOffsets: indices, toOffset: newOffset)
                    appContainer.navigationLayoutStore.setMore(order)
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

            Section("Chat") {
                Toggle("Show timestamps in chat list", isOn: $showChatTimestamps)
                ChatEncryptionRows(appContainer: appContainer)
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
                NavigationLink(value: AppRoute.termsOfUse) {
                    Text("Terms of Use")
                }
                Link("Report abuse", destination: viewModel.reportAbuseURL)
                Link("Child safety standards", destination: viewModel.childSafetyStandardsURL)
            }

            Section {
                NavigationLink(value: AppRoute.deleteAccount) {
                    Text("Delete Account").foregroundStyle(.red)
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
                    appContainer.matrixClientStore.clearSession()
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

    /// One reorderable row, offering swipe actions to move `destination` into whichever of the
    /// *other two* zones it isn't currently in (not just a single fixed target, since there are
    /// now three zones instead of two). "Move to Bottom Bar" is suppressed once the bar is at
    /// `NavigationLayoutStore.maximumBottomBarCount` (real `TabView` tab-overflow constraint, see
    /// that constant's doc comment), and every option is suppressed for a bottom-bar row once the
    /// bar is down to `minimumBottomBarCount` -- both mirror `move(_:to:)`'s own no-ops.
    @ViewBuilder
    private func navigationRow(_ destination: AppDestination, in zone: NavigationLayoutStore.Zone) -> some View {
        let store = appContainer.navigationLayoutStore
        let atBottomBarFloor = zone == .bottomBar && store.bottomBar.count <= NavigationLayoutStore.minimumBottomBarCount
        let bottomBarFull = store.bottomBar.count >= NavigationLayoutStore.maximumBottomBarCount
        Label(destination.label, systemImage: destination.systemImage)
            .swipeActions(edge: .trailing) {
                if !atBottomBarFloor {
                    if zone != .bottomBar, !bottomBarFull {
                        Button("Move to Bottom Bar") { store.move(destination, to: .bottomBar) }
                            .tint(.blue)
                    }
                    if zone != .topBar {
                        Button("Move to Top Bar") { store.move(destination, to: .topBar) }
                            .tint(.blue)
                    }
                    if zone != .more {
                        Button("Move to More") { store.move(destination, to: .more) }
                            .tint(.gray)
                    }
                }
            }
    }
}

/// Chat encryption rows -- see friendica-larpnet's `addon/larpnet_matrix/CLAUDE.md` "Encryption
/// modes". Standard mode (server holds the recovery passphrase, history unlocks itself): "show
/// my phrase" + switch to private. Private mode (or a server without escrow): the old manual
/// "Unlock chat history"/"Reset recovery key" entries, plus switch back to standard.
///
/// "Unlock chat history" exists because the restore flow is auto-prompted only once per launch
/// (`ChatView`'s `.sheet` on `ensureEncryption()`), and tapping "Later" there used to leave no
/// way back in -- confirmed live: a device stuck in that state shows every conversation as
/// empty, not just undecryptable placeholders. Safe to run even when already unlocked.
private struct ChatEncryptionRows: View {
    let appContainer: AppContainer
    @State private var encryption: MatrixEncryptionInfo?
    @State private var showResetConfirm = false
    @State private var showResetSheet = false
    @State private var showRestoreSheet = false
    @State private var showPrivateSheet = false
    @State private var showPhraseSheet = false
    @State private var showStandardConfirm = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var store: MatrixClientStore { appContainer.matrixClientStore }

    var body: some View {
        Group {
            if let encryption, encryption.isStandard || encryption.isPrivate {
                Text(
                    encryption.isStandard
                        ? "Encryption: standard. Larpnet keeps your chat history key, so history works automatically on every device. Server administrators can technically access it."
                        : "Encryption: private. Only you know your chat history key -- administrators can't access it. You need to enter it on new devices."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if encryption?.isStandard == true {
                Button("Show recovery phrase") { showPhraseSheet = true }
                Button("Turn on private mode") { showPrivateSheet = true }
            } else {
                Button("Unlock chat history") { showRestoreSheet = true }
                if encryption?.isPrivate == true {
                    Button {
                        showStandardConfirm = true
                    } label: {
                        if isBusy { ProgressView() } else { Text("Switch back to standard mode") }
                    }
                    .disabled(isBusy)
                }
                Button("Reset recovery key", role: .destructive) { showResetConfirm = true }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .task {
            encryption = store.encryptionInfo
            if let fresh = await store.fetchEncryptionInfo() { encryption = fresh }
        }
        .confirmationDialog(
            "This will remove access to chat history using the old key on new devices. This action cannot be undone.",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { showResetSheet = true }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Larpnet will keep your chat history key again, so you won't need to enter it on new devices. Server administrators will technically be able to access your messages.",
            isPresented: $showStandardConfirm,
            titleVisibility: .visible
        ) {
            Button("Yes, switch") { Task { await switchToStandard() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showResetSheet) {
            RecoveryKeyView(mode: .reset, appContainer: appContainer, onDone: { showResetSheet = false })
        }
        .sheet(isPresented: $showRestoreSheet) {
            RecoveryKeyView(
                mode: .restore, appContainer: appContainer,
                onDone: { showRestoreSheet = false },
                onSkip: { showRestoreSheet = false }
            )
        }
        .sheet(isPresented: $showPrivateSheet, onDismiss: { encryption = store.encryptionInfo }) {
            RecoveryKeyView(
                mode: .makePrivate, appContainer: appContainer,
                onDone: { showPrivateSheet = false },
                onSkip: { showPrivateSheet = false }
            )
        }
        .sheet(isPresented: $showPhraseSheet) {
            RecoveryPhraseView(phrase: encryption?.passphrase ?? "", onDone: { showPhraseSheet = false })
        }
    }

    private func switchToStandard() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await store.switchToStandard()
        } catch let error as MatrixClientStore.DeviceLockedError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Couldn't change the encryption mode. Please try again."
        }
        encryption = store.encryptionInfo
    }
}

/// Standard mode's "show my recovery phrase" -- the server-held passphrase, for use in another
/// Matrix client (e.g. Element's "Security Phrase").
private struct RecoveryPhraseView: View {
    let phrase: String
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Larpnet uses it automatically on all your devices -- you never need to " +
                        "type it. It's only useful if you want to use another Matrix app (e.g. " +
                        "Element, as a \"Security Phrase\"). Don't share it with anyone."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Section {
                    Text(phrase).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                Section {
                    Button("Close", action: onDone)
                }
            }
            .navigationTitle("Recovery phrase")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

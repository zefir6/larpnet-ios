import SwiftUI

/// Presented as a `.sheet` -- setup/restore from `ChatView` right after login (see
/// `MatrixClientStore.recoveryPromptKind()`), reset from `SettingsView`. Non-dismissable for
/// `.setup`/`.reset` until a key is chosen and confirmed (there's nothing sensible to skip to);
/// `.restore` allows "Later" since new messages still work without it, and `.makePrivate` can
/// be cancelled until a key is chosen.
struct RecoveryKeyView: View {
    @State private var viewModel: RecoveryKeyViewModel
    @Environment(\.dismiss) private var dismiss
    let onDone: () -> Void
    let onSkip: (() -> Void)?

    init(
        mode: RecoveryKeyViewModel.Mode, appContainer: AppContainer,
        onDone: @escaping () -> Void, onSkip: (() -> Void)? = nil, legacy: Bool = false
    ) {
        _viewModel = State(initialValue: RecoveryKeyViewModel(mode: mode, appContainer: appContainer, legacy: legacy))
        self.onDone = onDone
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.mode == .restore {
                    restoreBody
                } else if let key = viewModel.recoveryKey {
                    showKeyBody(key)
                } else {
                    chooseBody
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!isDismissable)
    }

    private var isDismissable: Bool {
        switch viewModel.mode {
        case .restore: return !viewModel.restoreSucceeded
        case .makePrivate: return viewModel.recoveryKey == nil && !viewModel.isBusy
        case .setup, .reset: return false
        }
    }

    private var title: String {
        switch viewModel.mode {
        case .setup: return "Set up recovery key"
        case .reset: return "Reset recovery key"
        case .restore: return "Unlock chat history"
        case .makePrivate: return "Turn on private mode"
        }
    }

    @ViewBuilder
    private var chooseBody: some View {
        Form {
            Section {
                Text(chooseExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task { await viewModel.chooseRandom() }
                } label: {
                    if viewModel.isBusy {
                        ProgressView()
                    } else {
                        Text("Generate a random key")
                    }
                }
                .disabled(viewModel.isBusy)
            }
            Section("Or enter your own phrase") {
                TextField("Passphrase…", text: $viewModel.passphraseInput)
                Button("Set phrase") { Task { await viewModel.choosePassphrase() } }
                    .disabled(viewModel.isBusy || viewModel.passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if viewModel.mode == .makePrivate, let onSkip {
                Section {
                    Button("Cancel", action: onSkip).disabled(viewModel.isBusy)
                }
            }
        }
    }

    private var chooseExplanation: String {
        switch viewModel.mode {
        case .reset:
            return "Your old key will stop working. Choose a new one -- random or your own phrase."
        case .makePrivate:
            return "Larpnet will stop keeping your chat history key -- administrators won't be " +
                "able to access your new messages. You'll need to enter the key or phrase you " +
                "choose now on every new device, and losing it means losing your history. " +
                "Choose a random key or your own phrase."
        case .setup, .restore:
            return "This key lets you read chat history on a new device. You can generate a random key or set your own, memorable phrase."
        }
    }

    @ViewBuilder
    private func showKeyBody(_ key: String) -> some View {
        Form {
            Section {
                Text(
                    "Save it somewhere safe (e.g. a password manager) -- no one else, including " +
                    "the server administrator, knows it or can recover it. If you set your own " +
                    "phrase, you can use that instead of this key on another device."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                Text(key).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            Section {
                Button("I've saved the key", action: onDone)
            }
        }
    }

    @ViewBuilder
    private var restoreBody: some View {
        Form {
            Section {
                Text(
                    viewModel.legacy
                        ? "Larpnet now remembers your chat history key for you, so you won't need " +
                          "to enter it again. To carry over your existing history, enter your old " +
                          "recovery key (or phrase) one last time. You can also do this later, or " +
                          "on another device where chat is already unlocked."
                        : "This is a new device -- enter your recovery key (or phrase, if you set one) " +
                          "to read earlier messages. You can do this later -- new messages will work " +
                          "already."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                TextField("Recovery key or phrase…", text: $viewModel.restoreInput)
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await viewModel.submitRestore() }
                } label: {
                    if viewModel.isBusy {
                        ProgressView()
                    } else {
                        Text("Unlock")
                    }
                }
                .disabled(viewModel.isBusy || viewModel.restoreInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let onSkip {
                    Button("Later", action: onSkip)
                }
            }
        }
        .onChange(of: viewModel.restoreSucceeded) { _, succeeded in
            if succeeded { onDone() }
        }
    }
}

import SwiftUI

/// Presented as a `.sheet` -- setup/restore from `ChatView` right after login (see
/// `MatrixClientStore.recoveryPromptKind()`), reset from `SettingsView`. Non-dismissable for
/// `.setup`/`.reset` until a key is chosen and confirmed (there's nothing sensible to skip to);
/// `.restore` allows "Later" since new messages still work without it.
struct RecoveryKeyView: View {
    @State private var viewModel: RecoveryKeyViewModel
    @Environment(\.dismiss) private var dismiss
    let onDone: () -> Void
    let onSkip: (() -> Void)?

    init(
        mode: RecoveryKeyViewModel.Mode, appContainer: AppContainer,
        onDone: @escaping () -> Void, onSkip: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: RecoveryKeyViewModel(mode: mode, appContainer: appContainer))
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
        .interactiveDismissDisabled(viewModel.mode != .restore || viewModel.restoreSucceeded)
    }

    private var title: String {
        switch viewModel.mode {
        case .setup: return "Ustaw klucz odzyskiwania"
        case .reset: return "Resetuj klucz odzyskiwania"
        case .restore: return "Odblokuj historię czatu"
        }
    }

    @ViewBuilder
    private var chooseBody: some View {
        Form {
            Section {
                Text(
                    viewModel.mode == .reset
                        ? "Stary klucz przestanie działać. Wybierz nowy -- losowy albo własną frazę."
                        : "Ten klucz pozwala odczytać historię czatu na nowym urządzeniu. Możesz wygenerować losowy klucz albo ustawić własną, łatwą do zapamiętania frazę."
                )
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
                        Text("Wygeneruj losowy klucz")
                    }
                }
                .disabled(viewModel.isBusy)
            }
            Section("Albo wpisz własną frazę") {
                TextField("Fraza…", text: $viewModel.passphraseInput)
                Button("Ustaw frazę") { Task { await viewModel.choosePassphrase() } }
                    .disabled(viewModel.isBusy || viewModel.passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func showKeyBody(_ key: String) -> some View {
        Form {
            Section {
                Text(
                    "Zapisz go w bezpiecznym miejscu (np. menedżerze haseł) -- nikt inny, w tym " +
                    "administrator serwera, go nie zna i nie może go odzyskać. Jeśli ustawiłeś/-aś " +
                    "własną frazę, możesz użyć jej zamiast tego klucza na innym urządzeniu."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                Text(key).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            Section {
                Button("Zapisałem/-am klucz", action: onDone)
            }
        }
    }

    @ViewBuilder
    private var restoreBody: some View {
        Form {
            Section {
                Text(
                    "To nowe urządzenie -- wpisz swój klucz odzyskiwania (albo frazę, jeśli taką " +
                    "ustawiłeś/-aś), aby odczytać wcześniejsze wiadomości. Możesz to zrobić później " +
                    "-- nowe wiadomości będą działać już teraz."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                TextField("Klucz odzyskiwania lub fraza…", text: $viewModel.restoreInput)
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
                        Text("Odblokuj")
                    }
                }
                .disabled(viewModel.isBusy || viewModel.restoreInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let onSkip {
                    Button("Później", action: onSkip)
                }
            }
        }
        .onChange(of: viewModel.restoreSucceeded) { _, succeeded in
            if succeeded { onDone() }
        }
    }
}

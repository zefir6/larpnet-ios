import Foundation

/// Direct port of the web client's `recovery.js`/`RecoveryKeyModal.jsx`:
/// - `.setup`/`.reset`: choose a random key or a custom passphrase, then show the resulting
///   encoded key once (there's no way to see it again -- we never keep a copy).
/// - `.restore`: this device doesn't have local access to already-existing recovery yet --
///   enter the saved key *or* the phrase it was set up with (see
///   `MatrixClientStore.restoreRecovery()`'s doc comment for why the same field accepts both).
@MainActor
@Observable
final class RecoveryKeyViewModel {
    enum Mode {
        case setup
        case reset
        case restore
    }

    let mode: Mode
    private(set) var recoveryKey: String?
    private(set) var isBusy = false
    private(set) var restoreSucceeded = false
    var passphraseInput = ""
    var restoreInput = ""
    var errorMessage: String?

    private let appContainer: AppContainer

    init(mode: Mode, appContainer: AppContainer) {
        self.mode = mode
        self.appContainer = appContainer
    }

    func chooseRandom() async {
        await choose(passphrase: nil)
    }

    func choosePassphrase() async {
        let trimmed = passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await choose(passphrase: trimmed)
    }

    func submitRestore() async {
        let trimmed = restoreInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await appContainer.matrixClientStore.restoreRecovery(input: trimmed)
            errorMessage = nil
            restoreSucceeded = true
        } catch {
            errorMessage = "Nieprawidłowy klucz lub fraza."
        }
    }

    private func choose(passphrase: String?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch mode {
            case .setup:
                recoveryKey = try await appContainer.matrixClientStore.setUpRecovery(passphrase: passphrase)
            case .reset:
                recoveryKey = try await appContainer.matrixClientStore.resetRecovery(passphrase: passphrase)
            case .restore:
                break
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

import Foundation

/// Direct port of the web client's `recovery.js`/`RecoveryKeyModal.jsx`:
/// - `.setup`/`.reset`: choose a random key or a custom passphrase, then show the resulting
///   encoded key once (there's no way to see it again -- we never keep a copy).
/// - `.restore`: this device doesn't have local access to already-existing recovery yet --
///   enter the saved key *or* the phrase it was set up with (see
///   `MatrixClientStore.restoreRecovery()`'s doc comment for why the same field accepts both).
///   `legacy`: the account is being moved to standard encryption mode but still has the user's
///   own old key -- after it unlocks this device, `ensureEncryption()` migrates.
/// - `.makePrivate`: same choose-then-show flow as `.reset`, for switching from standard to
///   private encryption mode (`MatrixClientStore.switchToPrivate`).
@MainActor
@Observable
final class RecoveryKeyViewModel {
    enum Mode {
        case setup
        case reset
        case restore
        case makePrivate
    }

    let mode: Mode
    private(set) var recoveryKey: String?
    private(set) var isBusy = false
    private(set) var restoreSucceeded = false
    var passphraseInput = ""
    var restoreInput = ""
    var errorMessage: String?

    let legacy: Bool
    private let appContainer: AppContainer

    init(mode: Mode, appContainer: AppContainer, legacy: Bool = false) {
        self.mode = mode
        self.appContainer = appContainer
        self.legacy = legacy
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
            if legacy {
                // Now unlocked with the old key -- migrate to the server passphrase. A failure
                // here just means the next session retries; history is already readable.
                _ = try? await appContainer.matrixClientStore.ensureEncryption()
            }
            errorMessage = nil
            restoreSucceeded = true
        } catch {
            errorMessage = "Invalid key or phrase."
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
            case .makePrivate:
                recoveryKey = try await appContainer.matrixClientStore.switchToPrivate(passphrase: passphrase)
            case .restore:
                break
            }
            errorMessage = nil
        } catch let error as MatrixClientStore.DeviceLockedError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

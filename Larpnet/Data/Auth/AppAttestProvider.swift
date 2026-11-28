import CryptoKit
import DeviceCheck
import Foundation

/// App Attest proof for in-app registration: a fresh Secure Enclave key, attested by Apple over
/// SHA256(server challenge), so friendica-larpnet can check the request comes from this genuine
/// app on a genuine device (`src/Security/LarpnetAttestation/AppAttest.php`). One key per
/// registration attempt -- registration is a one-shot request, so no assertions are needed.
///
/// Unavailable on the simulator and on some older devices; `attest` then throws and the
/// registration is sent without a proof, for the server to decide (it refuses by default).
enum AppAttestProvider {
    struct Proof: Sendable {
        /// Standard base64 of the CBOR attestation object.
        let attestation: String
        /// Standard base64 of the key identifier (as DCAppAttestService returns it).
        let keyId: String
    }

    enum AttestError: Error {
        case unsupported
    }

    static func attest(challenge: String) async throws -> Proof {
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw AttestError.unsupported }
        let keyId = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
        return Proof(attestation: attestation.base64EncodedString(), keyId: keyId)
    }
}

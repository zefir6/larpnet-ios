import XCTest
import MatrixRustSDK
@testable import Larpnet

/// Live end-to-end verification of `MatrixClientStore` against test.larpnet.pl -- see
/// `/Users/admin/.claude/plans/refactored-twirling-mountain.md` ("iOS: live-verify chat E2EE
/// on test.larpnet.pl"). Exercises the exact production code path two real accounts would go
/// through: `MatrixClientStore.ensureClient()` (real `POST larpnet_matrix` + JWT login),
/// `openOrCreateDirectRoom()`, `openTimeline()`, and `ChatTimelineHandle.send()` -- then confirms
/// a *second* account's device actually decrypts the message, not just that sending didn't
/// throw. This supersedes the old `MatrixChatSpikeTests` (deleted -- its only job was proving
/// the SDK integration was reachable at all, which `MatrixClientStore` now does for real).
///
/// Skipped unless both accounts' OAuth access tokens are provided via env vars -- never
/// hardcode credentials here (same convention as the file this replaces). Each token is a
/// real Friendica OAuth2 access token (Bearer), not a Matrix JWT -- `MatrixClientStore` mints
/// its own short-lived Matrix JWT internally via `POST larpnet_matrix`, exactly as the real app
/// does.
///
/// IMPORTANT, confirmed empirically while writing this test (do not "simplify" the ordering
/// below): Matrix only shares a room's megolm session with devices the sender's client already
/// sees as *joined* members at send time. Device B must log in AND join the room *before*
/// device A sends -- otherwise the message is permanently undecryptable by device B, the same
/// "sent by a device that didn't know about me yet" class of problem as the web client's
/// recovery-key work (`addon/larpnet_matrix/CLAUDE.md`), just via a different mechanism (no
/// cross-signing/key-backup exists on native at all -- see `MatrixClientStore`'s own doc
/// comment on that policy). Each side's client also needs an explicit `syncOnceV2()` call
/// (captured from `ensureClient()`'s return value) at the right moments rather than relying on
/// the background sync loop's own timing, so this test isn't flaky against real network
/// latency.
final class MatrixClientStoreIntegrationTests: XCTestCase {
    @MainActor
    func testCrossAccountSendAndDecrypt() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let tokenA = env["LARPNET_TEST_MATRIX_ACCOUNT_A_TOKEN"],
              let nicknameA = env["LARPNET_TEST_MATRIX_ACCOUNT_A_NICKNAME"],
              let tokenB = env["LARPNET_TEST_MATRIX_ACCOUNT_B_TOKEN"],
              let nicknameB = env["LARPNET_TEST_MATRIX_ACCOUNT_B_NICKNAME"] else {
            throw XCTSkip("""
                Set LARPNET_TEST_MATRIX_ACCOUNT_{A,B}_TOKEN/_NICKNAME (two distinct local \
                accounts' Friendica OAuth access tokens) to run this integration test.
                """)
        }
        let instance = env["LARPNET_TEST_INSTANCE"] ?? "https://test.larpnet.pl"
        guard let baseURL = URL(string: instance) else { throw XCTSkip("Invalid LARPNET_TEST_INSTANCE") }

        let session = URLSession(configuration: .default)
        let tokenStore = TokenStore()
        tokenStore.instanceBaseURL = instance
        // Force a fresh Matrix device for whichever account logs in next -- this test reuses
        // one Keychain-backed TokenStore for both accounts in turn (see doc comment above), so
        // without this, account B would inherit account A's device id string. That's actually
        // harmless on its own (Synapse device ids are scoped per-account, not global), but
        // clearing it here keeps each side's login unambiguous to read in a failure.
        tokenStore.matrixDeviceId = nil

        // Account A: log in, create (or find) the DM room, but do NOT send yet.
        tokenStore.accessToken = tokenA
        let clientA = FriendicaAPIClient(baseURL: baseURL, session: session, tokenStore: tokenStore)
        let storeA = MatrixClientStore(tokenStore: tokenStore, friendicaAPI: { clientA })
        let rawClientA = try await storeA.ensureClient()
        let roomId = try await storeA.openOrCreateDirectRoom(nickname: nicknameB)

        // Account B: log in (fresh device), find the same room, and JOIN it -- must happen
        // before account A sends, see this file's doc comment.
        tokenStore.matrixDeviceId = nil
        tokenStore.accessToken = tokenB
        let clientB = FriendicaAPIClient(baseURL: baseURL, session: session, tokenStore: tokenStore)
        let storeB = MatrixClientStore(tokenStore: tokenStore, friendicaAPI: { clientB })
        let rawClientB = try await storeB.ensureClient()
        guard let roomForB = try rawClientB.getRoom(roomId: roomId) else {
            XCTFail("Account B's client can't see the room account A just created/invited it to")
            return
        }
        if roomForB.membership() != .joined {
            try await roomForB.join()
        }

        // Make sure account A's client has actually seen B's join before sending -- otherwise
        // A's outgoing megolm session never gets shared with B's device at all.
        _ = try await rawClientA.syncOnceV2(settings: SyncSettingsV2(fullState: false))

        let handleA = try await storeA.openTimeline(roomId: roomId)
        let marker = "ios-e2ee-integration-test-\(UUID().uuidString.prefix(8))"
        try await handleA.send(text: marker)

        // Give B's client a few sync cycles to receive + decrypt the message, rather than
        // trusting the background loop's own long-poll timing.
        let handleB = try await storeB.openTimeline(roomId: roomId)
        var found = false
        for _ in 0..<10 {
            _ = try await rawClientB.syncOnceV2(settings: SyncSettingsV2(timeoutMs: 2000, fullState: false))
            if let snapshot = await handleB.messages.firstSnapshot(), snapshot.contains(where: { $0.body == marker }) {
                found = true
                break
            }
        }

        handleA.close()
        handleB.close()

        XCTAssertTrue(found, "Account B never received/decrypted account A's message (marker: \(marker))")
    }
}

private extension AsyncStream where Element: Sendable {
    /// Drains whatever's already been yielded into this stream without waiting indefinitely
    /// for a new element -- `ChatTimelineHandle.messages` re-yields the full snapshot on every
    /// diff batch, so the *latest* already-emitted value (if any) is exactly what we want to
    /// poll here, not a fresh one per call.
    func firstSnapshot() async -> Element? {
        await withTaskGroup(of: Element?.self) { group in
            group.addTask {
                var iterator = self.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

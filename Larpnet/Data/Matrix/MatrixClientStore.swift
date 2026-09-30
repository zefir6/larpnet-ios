import Foundation
import MatrixRustSDK

enum MatrixError: Error {
    case malformedIdentity
    case roomNotFound
    case invalidHomeserverUrl
    /// `deleteAllServerSideBackups()` gave up after `maxServerBackupDeleteAttempts` rounds --
    /// see that function's doc comment. Carries the last-seen backup version id for debugging.
    case tooManyServerSideBackups(lastVersion: String)
}

/// Owns the `MatrixRustSDK.Client` lifecycle for native chat -- see
/// `/Users/admin/.claude/plans/refactored-twirling-mountain.md` for the full design. Mirrors
/// the web client's `client/src/matrix.js` (`loginAndStart`) as closely as the native SDK's
/// shape allows:
///
/// - Login is a *fresh* JWT trade (`POST larpnet_matrix`) + `customLoginWithJwt` on every
///   launch -- never a persisted access token. Reusing the same `TokenStore.matrixDeviceId`
///   across launches makes Synapse re-issue a token for the same device rather than
///   registering a new one, so this is cheap and safe (confirmed against the web client's
///   identical pattern).
/// - The crypto/session store on disk (`sessionPaths`), keyed by the Matrix user id, DOES
///   persist across launches -- that's what makes E2EE history survive a relaunch. Lives in
///   the shared App Group container (`MatrixSessionPaths`), not this app's own `Application
///   Support` directory, so `NotificationServiceExtension` can reach the same store to decrypt
///   push notifications -- see that type's own doc comment for the one-time migration cost this
///   caused for anyone who installed before push notifications shipped.
/// - `ClientBuilder`'s `autoEnableCrossSigning`/`autoEnableBackups` are deliberately left at
///   their defaults (off) -- no interactive device-verification (SAS/emoji) UI, same policy as
///   web (`addon/larpnet_matrix/CLAUDE.md`'s "Why there's no device-verification UI"). This does
///   NOT mean no recovery key at all, though: the actual policy (see that same doc, updated once
///   web shipped user-chosen recovery passphrases) is "no *operator-derivable* key" -- a
///   recovery key/passphrase the user generates and holds themselves, never sent to or
///   knowable by the server, is fine and is what `setUpRecovery()`/`restoreRecovery()`/
///   `resetRecovery()` below implement (mirroring web's `client/src/recovery.js`). Confirmed via
///   a live spike against test.larpnet.pl (2026-09-25) that `Encryption.enableRecovery()` does
///   NOT hit the same JWT/UIA wall `bootstrapCrossSigning()` does on web -- it's a plain
///   secret-storage/backup operation, not a cross-signing key upload.
@MainActor
final class MatrixClientStore {
    private let tokenStore: TokenStore
    private let friendicaAPI: () throws -> FriendicaAPIClient

    private var client: Client?
    private var syncHandle: TaskHandle?
    private var roomListContinuation: AsyncStream<Void>.Continuation?
    /// nickname (lowercased) -> Friendica display name, from the same `contacts` list the web
    /// client's `resolveDisplayName()` uses -- covers anyone who's never opened chat themselves
    /// and so has no Matrix displayname yet.
    private var contactsByLocalpart: [String: String] = [:]
    private(set) var serverName: String?
    /// This deployment's Matrix push gateway URL (already includes the shared secret as a
    /// query param -- see `larpnet_matrix_push_gateway_url()` server-side), or nil if the
    /// server hasn't got push configured yet. Set once per `ensureClient()` login, same
    /// lifetime as `serverName`.
    private var pushGatewayUrl: String?

    init(tokenStore: TokenStore, friendicaAPI: @escaping () throws -> FriendicaAPIClient) {
        self.tokenStore = tokenStore
        self.friendicaAPI = friendicaAPI
    }

    /// Fires (with no payload -- just a "something changed, go re-fetch" signal) after every
    /// sync response lands, so `ChatViewModel` can refresh the room list live. Only one
    /// subscriber is supported at a time (the chat room list screen is the only consumer) --
    /// a second call replaces the first's continuation.
    func roomListUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.roomListContinuation = continuation
        }
    }

    /// Logs in if needed (idempotent -- returns the existing client on every call after the
    /// first this launch) and makes sure the background sync loop is running.
    @discardableResult
    func ensureClient() async throws -> Client {
        if let client { return client }

        let identity = try await friendicaAPI().matrixLogin()
        contactsByLocalpart = Dictionary(
            uniqueKeysWithValues: identity.contacts.map { ($0.nickname.lowercased(), $0.name) }
        )
        guard let resolvedServerName = Self.serverName(fromMxid: identity.userId) else {
            throw MatrixError.malformedIdentity
        }
        serverName = resolvedServerName
        pushGatewayUrl = identity.pushGatewayUrl

        let sessionDir = try MatrixSessionPaths.sessionDirectory(for: identity.userId)
        let newClient = try await ClientBuilder()
            .homeserverUrl(url: identity.homeserver)
            .sessionPaths(dataPath: sessionDir.path, cachePath: sessionDir.path)
            .build()
        try await newClient.customLoginWithJwt(
            jwt: identity.token, initialDeviceName: "larpnet iOS", deviceId: deviceId()
        )

        // One blocking sync before this call returns -- `rooms()`/`getDmRoom()`/`getRoom()`
        // all read local state that only exists once at least one sync has landed. Confirmed
        // against the throwaway `MatrixChatSpikeTests` this store supersedes: without this,
        // a caller that logs in and immediately checks `rooms()` races an empty local store.
        // The continuous background loop below is what keeps that state live afterward.
        _ = try await newClient.syncOnceV2(settings: SyncSettingsV2(fullState: true))

        client = newClient
        startSyncLoop(newClient)
        return newClient
    }

    func rooms() async throws -> [ChatRoom] {
        let client = try await ensureClient()
        var result: [ChatRoom] = []
        for room in client.rooms() where room.membership() == .joined {
            let name = await displayName(for: room)
            let (previewText, timestamp) = await preview(for: room)
            let unreadCount = (try? await room.roomInfo().numUnreadMessages).map(Int.init) ?? 0
            let avatarUrl = await avatarUrl(for: room)
            result.append(ChatRoom(
                id: room.id(), name: name, preview: previewText, timestamp: timestamp,
                unreadCount: unreadCount, avatarUrl: avatarUrl
            ))
        }
        return result.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    /// Cleans up the leftover duplicate DM rooms from before `openOrCreateDirectRoom()`
    /// reliably used `getDmRoom()`/`m.direct` -- same story as the web client's
    /// `findOrCreateDirectRoom()` (see its doc comment in `matrix.js`): a client that fails to
    /// find an existing DM creates a fresh one instead, and that duplicate is a real, separate
    /// room on the server, not just a display glitch. Confirmed live on a real account: the
    /// same contact had 4+ separate DM rooms, and which one a given client happened to open
    /// depended on lookup order -- explaining reports like "this conversation is empty" on one
    /// client while another shows real history for what looks like the same person.
    ///
    /// Run once per session, after login (see `ChatViewModel.loadInitial()`). For every
    /// 1:1-shaped room (exactly one other member) grouped by that member: if more than one
    /// room has a message, this is ambiguous (possibly two genuinely separate historical
    /// conversations) -- leave them all alone, just repoint `m.direct` at whichever was most
    /// recently active so new chats go to the right place. Otherwise the one room with a
    /// message (or, if none have one, a deterministic pick by room ID) is canonical: point
    /// `m.direct` at it and leave the empty duplicates, since a room with no messages has
    /// nothing to lose by leaving it (the same action the room list's own swipe-to-delete
    /// already performs on purpose).
    func consolidateDuplicateDirectRooms() async {
        guard let client = try? await ensureClient(), let selfId = try? client.userId() else { return }

        var byTarget: [String: [Room]] = [:]
        for room in client.rooms() where room.membership() == .joined || room.membership() == .invited {
            guard let iterator = try? await room.members() else { continue }
            var all: [RoomMember] = []
            while let chunk = iterator.nextChunk(chunkSize: 10), !chunk.isEmpty {
                all.append(contentsOf: chunk)
            }
            let active = all.filter { $0.membership == .join || $0.membership == .invite }
            guard active.count == 2, let other = active.first(where: { $0.userId != selfId }) else { continue }
            byTarget[other.userId, default: []].append(room)
        }

        for (targetMxid, roomsForTarget) in byTarget where roomsForTarget.count > 1 {
            var withMessage: [Room] = []
            for room in roomsForTarget where await hasMessageContent(room) {
                withMessage.append(room)
            }

            let canonical: Room
            var duplicatesToLeave: [Room] = []
            if withMessage.count > 1 {
                var best = withMessage[0]
                var bestTimestamp = await lastActiveTimestamp(best)
                for candidate in withMessage.dropFirst() {
                    let candidateTimestamp = await lastActiveTimestamp(candidate)
                    if (candidateTimestamp ?? .distantPast) > (bestTimestamp ?? .distantPast) {
                        best = candidate
                        bestTimestamp = candidateTimestamp
                    }
                }
                canonical = best
            } else if withMessage.count == 1 {
                canonical = withMessage[0]
                duplicatesToLeave = roomsForTarget.filter { $0.id() != canonical.id() }
            } else {
                let sorted = roomsForTarget.sorted { $0.id() < $1.id() }
                canonical = sorted[0]
                duplicatesToLeave = Array(sorted.dropFirst())
            }

            await setDirectRoomAccountData(client: client, targetMxid: targetMxid, roomId: canonical.id())

            for dup in duplicatesToLeave {
                try? await dup.leave()
            }
        }
    }

    private func hasMessageContent(_ room: Room) async -> Bool {
        let content: TimelineItemContent
        switch await room.latestEvent() {
        case .remote(_, _, _, _, let c), .local(_, _, _, let c, _): content = c
        case .none, .remoteInvite: return false
        }
        guard case .msgLike(let msgLike) = content else { return false }
        switch msgLike.kind {
        case .message, .unableToDecrypt: return true
        default: return false
        }
    }

    private func lastActiveTimestamp(_ room: Room) async -> Date? {
        switch await room.latestEvent() {
        case .remote(let timestamp, _, _, _, _), .local(let timestamp, _, _, _, _):
            return Self.date(from: timestamp)
        case .none, .remoteInvite:
            return nil
        }
    }

    /// Reads/writes `m.direct` directly (rather than going through `getDmRoom()`) since this is
    /// specifically about *repairing* that mapping, not looking a room up through it.
    private func setDirectRoomAccountData(client: Client, targetMxid: String, roomId: String) async {
        let raw = (try? await client.accountData(eventType: "m.direct")) ?? nil
        var direct = raw.flatMap { try? JSONDecoder().decode([String: [String]].self, from: Data($0.utf8)) } ?? [:]
        guard direct[targetMxid] != [roomId] else { return }
        direct[targetMxid] = [roomId]
        guard let encoded = try? JSONEncoder().encode(direct), let json = String(data: encoded, encoding: .utf8) else { return }
        try? await client.setAccountData(eventType: "m.direct", content: json)
    }

    /// Real room avatar, same hero-fallback shape as `displayName(for:)`: for a 1:1 DM, the
    /// room itself rarely has its own avatar set, so fall back to the other person's.
    private func avatarUrl(for room: Room) async -> String? {
        if let url = room.avatarUrl() { return url }
        let heroes = await room.heroes()
        return heroes.count == 1 ? heroes[0].avatarUrl : nil
    }

    /// Fetches a real avatar image's bytes for a `mxc://` URL (a sender's or room's) -- callers
    /// decode this into a `UIImage` and cache it themselves (see `MatrixAvatarView`); this layer
    /// only knows how to talk to the SDK's media loader, not about SwiftUI/caching.
    func avatarThumbnail(mxcUrl: String, size: Int = 96) async throws -> Data {
        let client = try await ensureClient()
        let source = try MediaSource.fromUrl(url: mxcUrl)
        return try await client.getMediaThumbnail(mediaSource: source, width: UInt64(size), height: UInt64(size))
    }

    /// Finds the existing 1:1 room with this nickname, or creates one -- same "1:1 == exactly
    /// this other member" heuristic and encrypted-by-default behavior as the web client's
    /// `findOrCreateDirectRoom()`. `nickname` is a plain Friendica nickname (e.g. from
    /// `Account.username`), not a full mxid -- this builds the mxid itself from `serverName`,
    /// same division of responsibility as `larpnet_matrix_dm_localpart()`'s doc comment
    /// describes for the web client.
    func openOrCreateDirectRoom(nickname: String) async throws -> String {
        // `serverName` is only populated by `ensureClient()`'s login flow -- reading it before
        // calling that (confirmed live: hitting this as the very first Matrix operation of the
        // app session, e.g. starting a chat without ever having opened the Chat tab first) threw
        // `malformedIdentity` unconditionally, regardless of whether `nickname` was ever valid.
        _ = try await ensureClient()
        guard let serverName else { throw MatrixError.malformedIdentity }
        return try await openOrCreateDirectRoom(targetMxid: "@\(nickname.lowercased()):\(serverName)")
    }

    /// Same as above, but for an already-fully-qualified mxid rather than a bare local
    /// nickname -- the new-chat picker's "enter a Matrix address" fallback, for someone who
    /// already knows the exact address (including on a different, federated homeserver, which
    /// the local-account search could never find in the first place).
    func openOrCreateDirectRoom(matrixId: String) async throws -> String {
        guard matrixId.hasPrefix("@"), matrixId.contains(":") else { throw MatrixError.malformedIdentity }
        return try await openOrCreateDirectRoom(targetMxid: matrixId)
    }

    private func openOrCreateDirectRoom(targetMxid: String) async throws -> String {
        let client = try await ensureClient()

        if let existing = try client.getDmRoom(userId: targetMxid) {
            return existing.id()
        }

        let roomId = try await client.createRoom(request: CreateRoomParameters(
            name: nil, isEncrypted: true, isDirect: true,
            visibility: .private, preset: .privateChat, invite: [targetMxid]
        ))
        return roomId
    }

    func openTimeline(roomId: String) async throws -> ChatTimelineHandle {
        let client = try await ensureClient()
        guard let room = try client.getRoom(roomId: roomId) else { throw MatrixError.roomNotFound }
        let timeline = try await room.timeline()
        // Same Friendica-name-first resolution the room list uses (`resolvedName`, via
        // `displayName(for:)`) -- without this, a per-message sender falls back straight to
        // their bare mxid localpart whenever they haven't set a Matrix displayname yet (the
        // common case for anyone who's never opened chat themselves), instead of the full name
        // the room list already knows how to show.
        let handle = ChatTimelineHandle(timeline: timeline) { [weak self] userId, fallbackDisplayName in
            self?.resolvedName(userId: userId, fallbackDisplayName: fallbackDisplayName) ?? (fallbackDisplayName ?? userId)
        }
        await handle.start()
        return handle
    }

    /// Members (join+invite, excluding self) plus the raw room-name state event and whether
    /// this is a group (more than one other member) -- mirrors the web client's
    /// `RoomInfoModal.jsx` (`others`/`isGroup` computed the same way). `rawName`, not
    /// `displayName()`, because for a 1:1 DM `displayName()` always prefers the other person's
    /// own name -- same reason `RoomInfoModal.jsx` hides rename there.
    func roomInfo(roomId: String) async throws -> ChatRoomInfo {
        let client = try await ensureClient()
        guard let room = try client.getRoom(roomId: roomId) else { throw MatrixError.roomNotFound }
        let selfId = try client.userId()

        let iterator = try await room.members()
        var all: [RoomMember] = []
        while let chunk = iterator.nextChunk(chunkSize: 100), !chunk.isEmpty {
            all.append(contentsOf: chunk)
        }
        let others = all.filter { ($0.membership == .join || $0.membership == .invite) && $0.userId != selfId }
        let members = others.map {
            ChatRoomMember(userId: $0.userId, displayName: resolvedName(userId: $0.userId, fallbackDisplayName: $0.displayName))
        }
        return ChatRoomInfo(roomId: roomId, rawName: room.rawName() ?? "", isGroup: members.count != 1, members: members)
    }

    func renameRoom(roomId: String, name: String) async throws {
        let client = try await ensureClient()
        guard let room = try client.getRoom(roomId: roomId) else { throw MatrixError.roomNotFound }
        try await room.setName(name: name)
    }

    /// `nickname` is a plain Friendica nickname, same convention as `openOrCreateDirectRoom()`.
    func inviteMember(roomId: String, nickname: String) async throws {
        let client = try await ensureClient()
        guard let room = try client.getRoom(roomId: roomId) else { throw MatrixError.roomNotFound }
        guard let serverName else { throw MatrixError.malformedIdentity }
        try await room.inviteUserById(userId: "@\(nickname.lowercased()):\(serverName)")
    }

    func removeMember(roomId: String, userId: String) async throws {
        let client = try await ensureClient()
        guard let room = try client.getRoom(roomId: roomId) else { throw MatrixError.roomNotFound }
        try await room.kickUser(userId: userId, reason: nil)
    }

    func leaveRoom(roomId: String) async throws {
        let client = try await ensureClient()
        guard let room = try client.getRoom(roomId: roomId) else { throw MatrixError.roomNotFound }
        try await room.leave()
    }

    /// Which recovery prompt (if any) `ChatView` should show right after login -- mirrors the
    /// web client's `getRecoveryStatus()`/`recoveryPrompt` (`recovery.js`/`App.jsx`).
    /// `.disabled` means this account has never set up recovery anywhere (prompt setup);
    /// `.incomplete` means recovery exists (set up on another device, or by this device in a
    /// past install) but this device hasn't unlocked it yet (prompt restore). `.unknown`
    /// resolves to one of the above via `waitForRecoveryState()` below; `.enabled` means this
    /// device already has it unlocked, nothing to prompt.
    enum RecoveryPromptKind {
        case needsSetup
        case needsRestore
    }

    func recoveryPromptKind() async throws -> RecoveryPromptKind? {
        switch try await waitForRecoveryState() {
        case .disabled: return .needsSetup
        case .incomplete: return .needsRestore
        case .enabled, .unknown: return nil
        }
    }

    /// Sets up recovery for the first time on this account (`RecoveryState.disabled`) -- a
    /// random key if `passphrase` is nil, otherwise derived from the phrase. Returns the
    /// encoded recovery key/phrase to show the user once (there's no way to see it again).
    func setUpRecovery(passphrase: String?) async throws -> String {
        let client = try await ensureClient()
        return try await client.encryption().enableRecovery(
            waitForBackupsToUpload: true, passphrase: passphrase, progressListener: RecoveryProgressBridge { _ in }
        )
    }

    /// Unlocks this device's access to existing cross-device history, using either the raw
    /// recovery key or the original passphrase -- `Encryption.recover()` accepts either as the
    /// same string (the underlying Rust crate's own doc comment gives the exact example
    /// `recovery.recover("my recovery key or passphrase")`).
    func restoreRecovery(input: String) async throws {
        let client = try await ensureClient()
        try await client.encryption().recover(recoveryKey: input)
    }

    /// Resets recovery when the user has forgotten their key/phrase -- same scope as web's
    /// `resetRecovery()` (see its doc comment in `client/src/recovery.js`/the addon's
    /// `CLAUDE.md`): this is "let me set a new key", not a guarantee that a device which
    /// already has the old keys locally loses access to old history.
    ///
    /// Two earlier versions of this function tried a plain `disableRecovery()`-then-`enable`
    /// pass (gated on `waitForRecoveryState()`, then retried a few times) and both were
    /// confirmed live to fail unreliably in different ways on the same account
    /// (`BackupNotEnabled` and `BackupExistsOnServer`, on different attempts). Two distinct
    /// problems had to be fixed, both confirmed by reading the actual Rust source
    /// (`Backups`/`Recovery` in `matrix-sdk`), not guessed:
    ///
    /// 1. **Server-side backup deletion must not trust the local crypto store.**
    ///    `Backups::disable()` only deletes the *one* backup version this device's local crypto
    ///    store currently happens to know about (`olm_machine.backup_machine().get_backup_keys()`);
    ///    it never asks the server what actually exists. If local knowledge is stale relative to
    ///    the server -- plausible on any account that's been through several earlier reset
    ///    attempts -- disabling "succeeds" while an orphaned version remains on the server, and
    ///    the next `enableRecovery()` correctly refuses to overwrite it (`BackupExistsOnServer`).
    ///    Fixed by copying the strategy **web's `matrix-js-sdk` already uses and never has this
    ///    problem with** (confirmed by reading its source, `rust-crypto/backup.js`'s
    ///    `deleteAllKeyBackupVersions()`): ask the *server* directly, in a loop -- "what's the
    ///    current backup version? delete it. ask again. repeat until there isn't one." The Rust
    ///    SDK's own equivalent (`Backups::disable_and_delete()`) exists but was never exposed
    ///    through this FFI, so `deleteAllServerSideBackups()` below replicates it with plain
    ///    authenticated HTTP calls using the session's own access token.
    ///
    /// 2. **`enableRecovery()` must be told the old backup is gone, not just have it deleted out
    ///    from under it.** Confirmed from the Rust source: `Enable`'s future only touches the
    ///    backup at all when the *local* `backups().are_enabled()` flag is false -- if a previous
    ///    session already activated a backup, that flag stays true regardless of what
    ///    `deleteAllServerSideBackups()` just did to the server, and `enableRecovery()` silently
    ///    skips recreating a backup entirely, rotating only the secret-storage key. Confirmed
    ///    live (on the Android port of this same fix): two resets in a row each returned a
    ///    distinct-looking "new" recovery key while zero requests touched `room_keys/version` and
    ///    the account was left with no working backup at all -- worse than the original bug,
    ///    since it also discards whatever backup existed. Fixed by calling `disableRecovery()`
    ///    first purely to flip that local flag to false; its own server-side deletion is the same
    ///    unreliable one-version attempt as above, which is why `deleteAllServerSideBackups()`
    ///    still runs unconditionally afterward. `disableRecovery()` is expected to throw here
    ///    (e.g. when local state was already stale, exactly the account shape problem 1 fixes) --
    ///    read from source that the local flag flips to `.unknown` before that error ever
    ///    propagates, so the throw is safe to ignore.
    func resetRecovery(passphrase: String?) async throws -> String {
        let client = try await ensureClient()
        try? await client.encryption().disableRecovery()
        try await deleteAllServerSideBackups()
        return try await client.encryption().enableRecovery(
            waitForBackupsToUpload: true, passphrase: passphrase, progressListener: RecoveryProgressBridge { _ in }
        )
    }

    private struct BackupVersionResponse: Decodable {
        let version: String
    }

    /// Deletes every key-backup version this account has on the server, asking the server fresh
    /// each time rather than trusting the SDK's local cache -- see `resetRecovery()`'s doc
    /// comment for the full "why". Bypasses `Encryption`/`Backups` entirely via plain
    /// authenticated Matrix Client-Server API calls, using the already-logged-in session's own
    /// access token (`Client.session()`) against its own homeserver (`Client.homeserver()`) --
    /// no new auth, just the same credentials the SDK is already using internally.
    ///
    /// Capped at `maxServerBackupDeleteAttempts` rounds as a sanity backstop against a genuinely
    /// pathological server response (e.g. something recreating a version between our delete and
    /// re-check) -- never expected to matter in practice; this account has needed at most a
    /// handful of deletes even after many earlier broken reset attempts this session.
    private func deleteAllServerSideBackups() async throws {
        let maxServerBackupDeleteAttempts = 20
        let client = try await ensureClient()
        let accessToken = try client.session().accessToken
        guard let homeserver = URL(string: client.homeserver()) else {
            throw MatrixError.invalidHomeserverUrl
        }

        func authedRequest(_ url: URL, method: String) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            return request
        }

        let versionUrl = homeserver.appendingPathComponent("_matrix/client/v3/room_keys/version")

        for _ in 0..<maxServerBackupDeleteAttempts {
            let (data, response) = try await URLSession.shared.data(for: authedRequest(versionUrl, method: "GET"))
            guard let httpResponse = response as? HTTPURLResponse else { break }
            if httpResponse.statusCode == 404 {
                return // Server confirms nothing left -- done.
            }
            guard httpResponse.statusCode == 200,
                  let current = try? JSONDecoder().decode(BackupVersionResponse.self, from: data) else {
                break // Unexpected shape -- don't loop on something we can't interpret.
            }

            let deleteUrl = homeserver.appendingPathComponent("_matrix/client/v3/room_keys/version/\(current.version)")
            let (_, deleteResponse) = try await URLSession.shared.data(for: authedRequest(deleteUrl, method: "DELETE"))
            guard let deleteHttpResponse = deleteResponse as? HTTPURLResponse,
                  (200..<300).contains(deleteHttpResponse.statusCode) else {
                break // A delete that didn't actually succeed isn't safe to loop past silently.
            }
        }

        // Re-check once more: either we exhausted the attempt cap, or a GET/DELETE returned an
        // unexpected shape above -- both `break` out of the loop rather than returning, so
        // confirm the end state before deciding whether this is actually a problem.
        let (data, response) = try await URLSession.shared.data(for: authedRequest(versionUrl, method: "GET"))
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            return
        }
        let lastVersion = (try? JSONDecoder().decode(BackupVersionResponse.self, from: data))?.version ?? "?"
        throw MatrixError.tooManyServerSideBackups(lastVersion: lastVersion)
    }

    /// `Encryption.recoveryState()` starts at `.unknown` right after login until the SDK's
    /// background crypto tasks resolve it -- waits for that via `recoveryStateListener` rather
    /// than polling.
    private func waitForRecoveryState() async throws -> RecoveryState {
        let client = try await ensureClient()
        let encryption = client.encryption()
        return await withCheckedContinuation { continuation in
            // Registers the listener *before* checking the current value (rather than the
            // other way around) so a transition happening in between the two can't be missed.
            // The listener's callback runs on the Rust side's own thread, so the "resume once"
            // guard needs real synchronization, not just a captured `var` -- see `OnceBox`.
            let box = OnceBox()
            let bridge = RecoveryStateBridge { state in
                guard state != .unknown else { return }
                box.fire { continuation.resume(returning: state) }
            }
            box.handle = encryption.recoveryStateListener(listener: bridge)
            let current = encryption.recoveryState()
            if current != .unknown {
                box.fire { continuation.resume(returning: current) }
            }
        }
    }

    /// Called alongside `TokenStore.clear()` at logout (see `SettingsView`) -- deletes the
    /// on-disk crypto store and the persisted device id, so a different account logging into
    /// this device next doesn't inherit either. Best-effort server-side `logout()` first (so
    /// the device is also cleanly removed from the account), but the local cleanup below runs
    /// regardless of whether that network call succeeds.
    func clearSession() {
        syncHandle?.cancel()
        syncHandle = nil
        roomListContinuation?.finish()
        roomListContinuation = nil
        contactsByLocalpart = [:]
        serverName = nil
        pushGatewayUrl = nil

        let oldClient = client
        client = nil

        Task.detached {
            let userId = try? oldClient?.userId()
            try? await oldClient?.logout()
            if let userId, let dir = try? MatrixSessionPaths.sessionDirectory(for: userId) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        tokenStore.clearMatrixDeviceId()
    }

    /// Registers this device's APNs token as a Matrix pusher, so Synapse starts calling
    /// larpnet_matrix's push gateway for new messages in any room this account is in. A no-op
    /// if the server hasn't got the gateway configured yet (`pushGatewayUrl` nil) -- same "safe
    /// until configured" convention the gateway itself follows.
    ///
    /// `format: .eventIdOnly` tells Synapse to never include full event content in the gateway
    /// call, matching the gateway's own guarantee independently -- both sides agree message
    /// content never reaches Apple, not just this one.
    ///
    /// `append: false`: replaces any existing pusher for this (app_id, pushkey) pair rather
    /// than accumulating duplicates across re-logins/token refreshes -- the pushkey (APNs
    /// device token) is the actual identity here, not the device id, so there's nothing worth
    /// keeping from a previous registration.
    func registerPusher(deviceToken: Data) async {
        guard let gatewayUrl = pushGatewayUrl else { return }
        guard let client = try? await ensureClient() else { return }
        let pushkey = Self.hexEncode(deviceToken)
        try? await client.setPusher(
            identifiers: PusherIdentifiers(pushkey: pushkey, appId: "pl.larpnet.ios"),
            kind: .http(data: HttpPusherData(url: gatewayUrl, format: .eventIdOnly, defaultPayload: "{}")),
            appDisplayName: "Larpnet iOS",
            deviceDisplayName: "Larpnet iOS",
            profileTag: nil,
            lang: "pl",
            append: false
        )
    }

    /// Called when the user turns off push notifications (Settings) without logging out
    /// entirely -- `clearSession()`'s own `logout()` call already removes every pusher for
    /// that device server-side, so this is only needed for the "still logged in, just disabled
    /// push" case.
    func unregisterPusher(deviceToken: Data) async {
        await unregisterPusher(pushkey: Self.hexEncode(deviceToken))
    }

    /// Same as above, taking the already hex-encoded pushkey directly -- `SettingsViewModel`
    /// only ever has `TokenStore.apnsDeviceTokenHex` cached (see that property's own doc
    /// comment for why: no live `Data` device token is re-fetchable on demand), not the raw
    /// `Data` `AppDelegate` receives fresh.
    func unregisterPusher(pushkey: String) async {
        guard let client = try? await ensureClient() else { return }
        try? await client.deletePusher(identifiers: PusherIdentifiers(pushkey: pushkey, appId: "pl.larpnet.ios"))
    }

    private static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private func startSyncLoop(_ client: Client) {
        syncHandle?.cancel()
        let bridge = SyncTickBridge { [weak self] in
            Task { @MainActor in self?.roomListContinuation?.yield() }
        }
        syncHandle = client.syncV2(settings: SyncSettingsV2(fullState: false), listener: bridge)
    }

    private func deviceId() -> String {
        if let existing = tokenStore.matrixDeviceId { return existing }
        let generated = UUID().uuidString
        tokenStore.matrixDeviceId = generated
        return generated
    }

    private nonisolated static func serverName(fromMxid mxid: String) -> String? {
        guard let colonIndex = mxid.firstIndex(of: ":") else { return nil }
        return String(mxid[mxid.index(after: colonIndex)...])
    }

    fileprivate nonisolated static func localpart(of mxid: String) -> String? {
        guard mxid.hasPrefix("@"), let colonIndex = mxid.firstIndex(of: ":") else { return nil }
        return String(mxid[mxid.index(after: mxid.startIndex)..<colonIndex]).lowercased()
    }

    /// Room-list display name -- same algorithm as the web client's `roomDisplayName()`: for a
    /// 1:1 DM, prefer the Friendica name we already know (covers a partner who's never opened
    /// chat themselves, so has no Matrix displayname yet) over the SDK's own hero-based
    /// summary; fall back to the SDK's computed name (handles group rooms) otherwise.
    private func displayName(for room: Room) async -> String {
        let heroes = await room.heroes()
        if heroes.count == 1 {
            return resolvedName(userId: heroes[0].userId, fallbackDisplayName: heroes[0].displayName)
        }
        if let name = room.displayName(), !name.isEmpty { return name }
        return "Chat"
    }

    /// Shared by the room-list hero name above and `roomInfo()`'s member list: prefer the
    /// Friendica name we already know (covers a member who's never opened chat themselves, so
    /// has no Matrix displayname yet) over the SDK-reported displayname, then fall back to the
    /// bare localpart.
    private func resolvedName(userId: String, fallbackDisplayName: String?) -> String {
        if let localpart = Self.localpart(of: userId), let resolved = contactsByLocalpart[localpart] {
            return resolved
        }
        if let name = fallbackDisplayName, !name.isEmpty { return name }
        return Self.localpart(of: userId) ?? userId
    }

    private func preview(for room: Room) async -> (text: String?, timestamp: Date?) {
        switch await room.latestEvent() {
        case .none:
            return (nil, nil)
        case .remoteInvite(let timestamp, _, _):
            return (nil, Self.date(from: timestamp))
        case .remote(let timestamp, _, _, _, let content):
            return (Self.previewText(for: content), Self.date(from: timestamp))
        case .local(let timestamp, _, _, let content, _):
            return (Self.previewText(for: content), Self.date(from: timestamp))
        }
    }

    private static func previewText(for content: TimelineItemContent) -> String? {
        guard case .msgLike(let msgLike) = content else { return nil }
        switch msgLike.kind {
        case .message(let message): return message.body
        case .unableToDecrypt: return "🔒"
        default: return nil
        }
    }

    private static func date(from timestamp: Timestamp) -> Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }
}

/// One open room's timeline: applies `TimelineDiff`s to a running snapshot and republishes the
/// whole snapshot (not just the delta) as `ChatMessage`s -- simple over clever, since a DM's
/// timeline is never large enough for delta-based list diffing to matter here the way it would
/// for Element X's general-purpose room list.
@MainActor
final class ChatTimelineHandle {
    private let timeline: Timeline
    /// Friendica-name-first resolution for a sender, same as the room list's `resolvedName` --
    /// injected rather than duplicated so this stays in sync with `MatrixClientStore`'s own
    /// `contactsByLocalpart` lookup (see `openTimeline`'s call site).
    private let resolveDisplayName: (String, String?) -> String
    private var listenerHandle: TaskHandle?
    private var items: [TimelineItem] = []
    private let continuation: AsyncStream<[ChatMessage]>.Continuation
    let messages: AsyncStream<[ChatMessage]>

    init(timeline: Timeline, resolveDisplayName: @escaping (String, String?) -> String) {
        self.timeline = timeline
        self.resolveDisplayName = resolveDisplayName
        var continuation: AsyncStream<[ChatMessage]>.Continuation!
        self.messages = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {
        let bridge = TimelineDiffBridge { [weak self] diffs in
            Task { @MainActor in self?.apply(diffs) }
        }
        listenerHandle = await timeline.addListener(listener: bridge)
        await loadInitialHistory()
    }

    /// `addListener` only delivers whatever's already cached locally for this room -- for a
    /// conversation with no *recent* activity, that can be nothing at all, even once this
    /// device's decryption keys are in place (confirmed live: a real conversation with history
    /// on other clients showed "No messages yet" here, on an unlock-chat-history-completed
    /// device, until backward pagination was requested). The SDK never backfills this on its
    /// own; a client has to explicitly call `paginateBackwards()`. Bounded at 3 rounds (~90
    /// events) as a sane first-open depth, stopping early once the server reports the actual
    /// start of the room's timeline -- not gated on checking `items` afterward, since the
    /// listener delivers diffs asynchronously and could still be racing this call.
    private func loadInitialHistory() async {
        for _ in 0..<3 {
            guard let hitStart = try? await timeline.paginateBackwards(numEvents: 30), !hitStart else { break }
        }
    }

    func send(text: String) async throws {
        _ = try await timeline.send(msg: messageEventContentFromMarkdown(md: text))
    }

    /// Stops the timeline listener -- call when the thread screen closes, so the room's
    /// timeline diff subscription doesn't keep running (and retaining `self`) after the view
    /// that cares about it is gone.
    func close() {
        listenerHandle?.cancel()
        continuation.finish()
    }

    private func apply(_ diffs: [TimelineDiff]) {
        for diff in diffs {
            switch diff {
            case .append(let values): items.append(contentsOf: values)
            case .clear: items.removeAll()
            case .pushFront(let value): items.insert(value, at: 0)
            case .pushBack(let value): items.append(value)
            case .popFront: if !items.isEmpty { items.removeFirst() }
            case .popBack: if !items.isEmpty { items.removeLast() }
            case .insert(let index, let value): items.insert(value, at: Int(index))
            case .set(let index, let value): items[Int(index)] = value
            case .remove(let index): items.remove(at: Int(index))
            case .truncate(let length): items = Array(items.prefix(Int(length)))
            case .reset(let values): items = values
            }
        }
        continuation.yield(items.compactMap { self.chatMessage(from: $0) })
    }

    private func chatMessage(from item: TimelineItem) -> ChatMessage? {
        guard let event = item.asEvent(), case .msgLike(let msgLike) = event.content else { return nil }
        let body: String
        let isUndecryptable: Bool
        switch msgLike.kind {
        case .message(let message): body = message.body; isUndecryptable = false
        case .unableToDecrypt: body = ""; isUndecryptable = true
        case .redacted: return nil
        default: return nil
        }
        var sdkDisplayName: String?
        var avatarUrl: String?
        if case .ready(let displayName, _, let profileAvatarUrl, _, _) = event.senderProfile {
            sdkDisplayName = displayName?.isEmpty == false ? displayName : nil
            avatarUrl = profileAvatarUrl
        }
        return ChatMessage(
            id: item.uniqueId().id, isOwn: event.isOwn, body: body,
            timestamp: Date(timeIntervalSince1970: Double(event.timestamp) / 1000),
            senderId: event.isOwn ? nil : event.sender,
            senderDisplayName: event.isOwn ? nil : resolveDisplayName(event.sender, sdkDisplayName),
            senderAvatarUrl: event.isOwn ? nil : avatarUrl,
            isUndecryptable: isUndecryptable
        )
    }
}

/// Plain `TimelineListener`/`SyncListenerV2` adapters -- MatrixRustSDK's callback protocols
/// require a class conforming directly, so a stored closure needs this thin wrapper rather
/// than being usable as the listener itself. The Rust side calls these from its own worker
/// thread, not the main actor -- callers hop back via `Task { @MainActor in ... }` themselves
/// (see `MatrixClientStore.startSyncLoop`/`ChatTimelineHandle.start`), not here.
private final class TimelineDiffBridge: TimelineListener, Sendable {
    private let handler: @Sendable ([TimelineDiff]) -> Void
    init(handler: @escaping @Sendable ([TimelineDiff]) -> Void) { self.handler = handler }
    func onUpdate(diff: [TimelineDiff]) { handler(diff) }
}

private final class SyncTickBridge: SyncListenerV2, Sendable {
    private let handler: @Sendable () -> Void
    init(handler: @escaping @Sendable () -> Void) { self.handler = handler }
    func onUpdate(response: SyncResponseV2) { handler() }
}

/// Runs `block` at most once, guarded by a lock -- `waitForRecoveryState()`'s listener callback
/// fires on the Rust side's own thread, so a plain captured `var` isn't safe here (the compiler
/// rejects it outright under strict concurrency checking); this is the minimal `@unchecked
/// Sendable` box that satisfies it. `handle` itself is only ever written once, synchronously,
/// before the listener that reads it can possibly fire.
private final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    var handle: TaskHandle?

    func fire(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        handle?.cancel()
        block()
    }
}

private final class RecoveryStateBridge: RecoveryStateListener, Sendable {
    private let handler: @Sendable (RecoveryState) -> Void
    init(handler: @escaping @Sendable (RecoveryState) -> Void) { self.handler = handler }
    func onUpdate(status: RecoveryState) { handler(status) }
}

private final class RecoveryProgressBridge: EnableRecoveryProgressListener, Sendable {
    private let handler: @Sendable (EnableRecoveryProgress) -> Void
    init(handler: @escaping @Sendable (EnableRecoveryProgress) -> Void) { self.handler = handler }
    func onUpdate(status: EnableRecoveryProgress) { handler(status) }
}

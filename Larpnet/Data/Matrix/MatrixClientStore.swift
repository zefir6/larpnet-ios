import Foundation
import MatrixRustSDK

enum MatrixError: Error {
    case malformedIdentity
    case roomNotFound
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
            result.append(ChatRoom(id: room.id(), name: name, preview: previewText, timestamp: timestamp))
        }
        return result.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    /// Finds the existing 1:1 room with this nickname, or creates one -- same "1:1 == exactly
    /// this other member" heuristic and encrypted-by-default behavior as the web client's
    /// `findOrCreateDirectRoom()`. `nickname` is a plain Friendica nickname (e.g. from
    /// `Account.username`), not a full mxid -- this builds the mxid itself from `serverName`,
    /// same division of responsibility as `larpnet_matrix_dm_localpart()`'s doc comment
    /// describes for the web client.
    func openOrCreateDirectRoom(nickname: String) async throws -> String {
        let client = try await ensureClient()
        guard let serverName else { throw MatrixError.malformedIdentity }
        let targetMxid = "@\(nickname.lowercased()):\(serverName)"

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
        let handle = ChatTimelineHandle(timeline: timeline)
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
    /// already has the old keys locally loses access to old history. `resetRecoveryKey()`/
    /// `recoverAndReset()` exist on this SDK but don't accept a passphrase -- a custom-
    /// passphrase reset goes through disable-then-enable instead, which reaches the same end
    /// state (a fresh secret-storage key/backup version) via the same path `setUpRecovery()`
    /// already uses.
    func resetRecovery(passphrase: String?) async throws -> String {
        let client = try await ensureClient()
        let encryption = client.encryption()
        try await encryption.disableRecovery()
        return try await encryption.enableRecovery(
            waitForBackupsToUpload: true, passphrase: passphrase, progressListener: RecoveryProgressBridge { _ in }
        )
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

    private nonisolated static func localpart(of mxid: String) -> String? {
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
        return "Rozmowa"
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
    private var listenerHandle: TaskHandle?
    private var items: [TimelineItem] = []
    private let continuation: AsyncStream<[ChatMessage]>.Continuation
    let messages: AsyncStream<[ChatMessage]>

    init(timeline: Timeline) {
        self.timeline = timeline
        var continuation: AsyncStream<[ChatMessage]>.Continuation!
        self.messages = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {
        let bridge = TimelineDiffBridge { [weak self] diffs in
            Task { @MainActor in self?.apply(diffs) }
        }
        listenerHandle = await timeline.addListener(listener: bridge)
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
        continuation.yield(items.compactMap(Self.chatMessage(from:)))
    }

    private static func chatMessage(from item: TimelineItem) -> ChatMessage? {
        guard let event = item.asEvent(), case .msgLike(let msgLike) = event.content else { return nil }
        let body: String
        switch msgLike.kind {
        case .message(let message): body = message.body
        case .unableToDecrypt: body = "🔒"
        case .redacted: return nil
        default: return nil
        }
        return ChatMessage(
            id: item.uniqueId().id, isOwn: event.isOwn, body: body,
            timestamp: Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
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

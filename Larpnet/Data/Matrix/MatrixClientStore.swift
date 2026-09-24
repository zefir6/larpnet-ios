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
///   persist across launches -- that's what makes E2EE history survive a relaunch.
/// - No cross-signing / secret-storage bootstrap -- explicit policy carried over from web
///   (`addon/larpnet_matrix/CLAUDE.md`'s "Why there's no device-verification UI": a single
///   device sends/receives E2EE fine without it, and an operator-derivable recovery key is a
///   security regression, not a convenience). `ClientBuilder`'s `autoEnableCrossSigning`/
///   `autoEnableBackups` are deliberately left at their defaults (off) -- do not turn them on
///   without re-reading that policy first.
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

        let sessionDir = try Self.sessionDirectory(for: identity.userId)
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

        let oldClient = client
        client = nil

        Task.detached {
            let userId = try? oldClient?.userId()
            try? await oldClient?.logout()
            if let userId, let dir = try? Self.sessionDirectory(for: userId) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        tokenStore.clearMatrixDeviceId()
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

    /// One `Application Support` subdirectory per Matrix user id -- reused across launches
    /// (see this type's own doc comment) and removed wholesale by `clearSession()`. `nonisolated`
    /// -- `clearSession()` calls this from a detached (off-main-actor) cleanup task, and it
    /// touches no instance state.
    private nonisolated static func sessionDirectory(for userId: String) throws -> URL {
        let safe = userId.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: ":", with: "_")
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("MatrixSession", isDirectory: true).appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Room-list display name -- same algorithm as the web client's `roomDisplayName()`: for a
    /// 1:1 DM, prefer the Friendica name we already know (covers a partner who's never opened
    /// chat themselves, so has no Matrix displayname yet) over the SDK's own hero-based
    /// summary; fall back to the SDK's computed name (handles group rooms) otherwise.
    private func displayName(for room: Room) async -> String {
        let heroes = await room.heroes()
        if heroes.count == 1 {
            let hero = heroes[0]
            if let localpart = Self.localpart(of: hero.userId), let resolved = contactsByLocalpart[localpart] {
                return resolved
            }
            if let name = hero.displayName, !name.isEmpty { return name }
            return Self.localpart(of: hero.userId) ?? hero.userId
        }
        if let name = room.displayName(), !name.isEmpty { return name }
        return "Rozmowa"
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

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
    /// Last known chat encryption mode -- from the login response, refreshed by
    /// `fetchEncryptionInfo()` and after every mode change. Nil = server predates encryption
    /// modes (or the call failed): behave like private mode.
    private(set) var encryptionInfo: MatrixEncryptionInfo?

    /// Number of rooms with unread messages, muted rooms excluded -- the same number Synapse
    /// pushes as the badge (`counts.unread`, see friendica-larpnet's larpnet_matrix CLAUDE.md
    /// "Chat notifications") and the web bubble shows. Recounted after every sync (see
    /// `startSyncLoop`), so the Chat tab badge and the app icon are right without the chat
    /// screen ever having been opened. Wired up by `AppContainer`.
    var onUnreadCountChange: ((Int) -> Void)?
    private var isRecountingUnread = false

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
        encryptionInfo = identity.encryption

        if tokenStore.matrixSessionResetVersion < Self.matrixSessionResetVersion {
            await discardLocalSession(identity)
            tokenStore.matrixSessionResetVersion = Self.matrixSessionResetVersion
        }

        let sessionDir = try MatrixSessionPaths.sessionDirectory(for: identity.userId)
        if tokenStore.matrixEventCacheResetVersion < Self.matrixEventCacheResetVersion {
            Self.discardEventCache(in: sessionDir)
            tokenStore.matrixEventCacheResetVersion = Self.matrixEventCacheResetVersion
        }
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
        await Self.startEventCache(newClient)
        _ = try await newClient.syncOnceV2(settings: SyncSettingsV2(fullState: true))
        // Fresh store: there was no room to open a timeline on until now. Nothing was cached
        // before this either, so nothing is missing -- an empty cache paginates from the end.
        await Self.startEventCache(newClient)

        client = newClient
        startSyncLoop(newClient)
        return newClient
    }

    /// Makes the SDK's event cache (where every room timeline reads its events from) start
    /// recording synced events. The SDK only does that once some room's timeline has been
    /// built, and the plain v2 sync this app uses never builds one -- so everything synced
    /// before the first chat was opened in a run went unrecorded. A room that already had
    /// cached events then showed those and nothing newer, for good: back-pagination only fills
    /// in *before* the oldest cached event (found on larpnet-android, 2026-10-13: a message
    /// received while the app was closed never appeared, even after reopening the room).
    ///
    /// The FFI has no direct call for this, so: build one room's timeline and drop it right
    /// away -- the subscription it starts lasts as long as the client. No-op with no rooms yet.
    private static func startEventCache(_ client: Client) async {
        guard let room = client.rooms().first else { return }
        _ = try? await room.timeline()
    }

    /// Bump to make every install drop its local timeline cache once -- see
    /// `discardEventCache(in:)`. 1 = caches written before `startEventCache(_:)` existed, which
    /// can be missing messages (2026-10-13).
    private static let matrixEventCacheResetVersion = 1

    /// One-time removal of the event cache database (only the timeline cache -- not the crypto
    /// or state stores), for caches written before `startEventCache(_:)` existed. The SDK
    /// recreates it empty and refills it from the server. Must run before the client is built.
    private static func discardEventCache(in sessionDir: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("matrix-sdk-event-cache.sqlite3") {
            try? fm.removeItem(at: file)
        }
    }

    /// Room ids currently being joined by `acceptLocalInvites` -- `rooms()` runs on every sync
    /// update, so the same invite would otherwise be joined several times concurrently.
    private var joiningInvites: Set<String> = []

    /// Auto-accepts invites from other users on this homeserver -- the actual reason "messages
    /// never arrive": starting a chat creates an encrypted room and only *invites* the other
    /// person, and no client of ours ever joined an invited room (this one didn't even list
    /// them, see `rooms()`). An invited user sees none of a room's timeline, so the recipient's
    /// side stayed empty forever. Invites from other servers are left alone (prod federates;
    /// auto-joining arbitrary remote invites would be a spam vector). `Room.join()` marks the
    /// room as a DM in our own `m.direct` itself when the invite had `is_direct`, so
    /// `openOrCreateDirectRoom()` then resolves to the same room. Same policy as the web
    /// client's `autoJoinLocalInvites()` and larpnet-android's `acceptLocalInvites()`.
    private func acceptLocalInvites(_ client: Client) async {
        guard let ownServer = serverName else { return }
        for room in client.rooms() where room.membership() == .invited {
            let roomId = room.id()
            guard !joiningInvites.contains(roomId) else { continue }
            guard let inviter = try? await room.inviter()?.userId,
                  Self.serverName(fromMxid: inviter) == ownServer else { continue }
            joiningInvites.insert(roomId)
            defer { joiningInvites.remove(roomId) }
            try? await room.join()
        }
    }

    func rooms() async throws -> [ChatRoom] {
        let client = try await ensureClient()
        await acceptLocalInvites(client)
        var result: [ChatRoom] = []
        let mutes = await muteStates(client)
        for room in client.rooms() where room.membership() == .joined {
            let name = await displayName(for: room)
            let (previewText, timestamp) = await preview(for: room)
            let muted = mutes.keys.contains(room.id())
            let unreadCount = muted ? 0 : await Self.unreadCount(of: room)
            let avatarUrl = await avatarUrl(for: room)
            let peerUserId = room.avatarUrl() == nil ? await peerUserId(for: room) : nil
            result.append(ChatRoom(
                id: room.id(), name: name, preview: previewText, timestamp: timestamp,
                unreadCount: unreadCount, avatarUrl: avatarUrl, peerUserId: peerUserId,
                muted: muted, mutedUntil: mutes[room.id()].flatMap { $0 }
            ))
        }
        onUnreadCountChange?(result.filter { $0.unreadCount > 0 }.count)
        return result.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    /// Up to `limit` local Larpnet nicknames to suggest as "start a new chat" recipients,
    /// ranked by last-activity recency across existing 1:1 DM rooms -- the only interaction
    /// signal actually available (no per-room message-count tracking exists). Federated peers
    /// are excluded, same as `SearchView.chatRecipientMode`'s own filter: a remote account has
    /// no Friendica nickname for `SearchViewModel` to resolve via `searchAccounts`. Doesn't go
    /// through `rooms()`/`ChatRoom.peerUserId` since that field is only populated when the raw
    /// SDK room has no avatar set -- irrelevant here, this only needs the peer mxid and a
    /// recency ordering.
    func suggestedDirectChatNicknames(limit: Int = 8) async -> [String] {
        guard let client = try? await ensureClient() else { return [] }
        var scored: [(nickname: String, timestamp: Date?)] = []
        for room in client.rooms() where room.membership() == .joined {
            let others = await otherMemberIds(of: room)
            guard others.count == 1,
                  Self.serverName(fromMxid: others[0]) == serverName,
                  let localpart = Self.localpart(of: others[0])
            else { continue }
            let (_, timestamp) = await preview(for: room)
            scored.append((nickname: localpart, timestamp: timestamp))
        }
        var seen = Set<String>()
        var result: [String] = []
        for entry in scored.sorted(by: { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }) {
            guard seen.insert(entry.nickname).inserted else { continue }
            result.append(entry.nickname)
            if result.count == limit { break }
        }
        return result
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

    /// Everyone in `room` but us (joined or invited, bots excluded). Not `room.heroes()`: under
    /// the plain v2 sync this app uses, Synapse sends no room-summary heroes, so `heroes()` was
    /// always empty (confirmed on larpnet-android, 2026-10-14) -- every 1:1 row fell through to
    /// the SDK's computed name (the partner's bare localpart, e.g. "borsuk") with initials only.
    /// Locally-known members first; the network `/members` fetch only for a room whose member
    /// list was never loaded (the SDK caches it afterwards).
    private func otherMemberIds(of room: Room) async -> [String] {
        let own = room.ownUserId()
        let local = ((try? await room.activeHumanMemberIdsNoSync()) ?? []).filter { $0 != own }
        if !local.isEmpty { return local }
        return ((try? await room.activeHumanMemberIds()) ?? []).filter { $0 != own }
    }

    /// The other member of a 1:1 room, nil for groups -- used for the Friendica-photo avatar on
    /// room-list rows (see `friendicaAvatarURL(userId:)`).
    private func peerUserId(for room: Room) async -> String? {
        let others = await otherMemberIds(of: room)
        return others.count == 1 ? others[0] : nil
    }

    /// Real room avatar: for a 1:1 DM the room itself rarely has its own avatar set, so fall
    /// back to the other person's.
    private func avatarUrl(for room: Room) async -> String? {
        if let url = room.avatarUrl() { return url }
        guard let peer = await peerUserId(for: room) else { return nil }
        return try? await room.memberAvatarUrl(userId: peer)
    }

    /// The Friendica profile photo (80px `/photo/avatar/<nickname>.jpg`) for a user on this
    /// homeserver, nil for anyone else. Every local Matrix account is a Friendica account whose
    /// localpart is the lowercased nickname (`larpnet_matrix_localpart()` server-side), and that
    /// photo URL is public -- unlike the SDK's sender/member profiles, which under plain v2
    /// sync's lazy-loaded members are often not loaded, so a Matrix `avatar_url` alone mostly
    /// left chat showing initials only. Same source the web client's `avatarUrlForUserId()` uses.
    func friendicaAvatarURL(userId: String?) -> URL? {
        guard let userId, let localpart = Self.localpart(of: userId),
              let serverName, Self.serverName(fromMxid: userId) == serverName,
              var base = tokenStore.instanceBaseURL else { return nil }
        if !base.hasPrefix("http") { base = "https://" + base }
        if !base.hasSuffix("/") { base += "/" }
        let encoded = localpart.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? localpart
        return URL(string: base + "photo/avatar/" + encoded + ".jpg")
    }

    /// Settings' chat name style -- also nudges the room list to re-resolve its names now,
    /// rather than only on the next sync.
    func setChatNameDisplay(_ mode: ChatNameDisplay) {
        UserDefaults.standard.set(mode.rawValue, forKey: ChatNameDisplay.defaultsKey)
        roomListContinuation?.yield()
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
            ChatRoomMember(
                userId: $0.userId, displayName: resolvedName(userId: $0.userId, fallbackDisplayName: $0.displayName),
                avatarUrl: $0.avatarUrl
            )
        }
        return ChatRoomInfo(
            roomId: roomId, rawName: room.rawName() ?? "", isGroup: members.count != 1, members: members,
            avatarUrl: room.avatarUrl()
        )
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
        /// Standard mode, but the account still has the user's own key from before encryption
        /// modes existed and this device was never unlocked -- see `ensureEncryption()`.
        case needsRestoreLegacy
    }

    /// Thrown by `switchToPrivate`/`switchToStandard` when this device isn't unlocked -- both
    /// rotate secret storage via `resetRecovery`, which is only clean from a device that
    /// already holds the cross-signing private keys.
    struct DeviceLockedError: LocalizedError {
        var errorDescription: String? { "Unlock chat history on this device first." }
    }

    @discardableResult
    func fetchEncryptionInfo() async -> MatrixEncryptionInfo? {
        guard let info = try? await friendicaAPI().matrixEncryption(action: "get") else { return nil }
        encryptionInfo = info
        return info
    }

    /// Runs once per session after login (replaces the old unconditional
    /// `recoveryPromptKind()` prompt). Same decision tree as the web client's
    /// `ensureEncryption()` (friendica-larpnet `addon/larpnet_matrix/client/src/encryption.js`)
    /// and larpnet-android's `MatrixRepository.ensureEncryption()` -- keep the three in step:
    ///
    /// - Private mode / no escrow: returns the old manual prompt kind, unchanged.
    /// - Standard, pending: set up (`.disabled`) or force-reset (`.enabled` -- migrates a legacy
    ///   user-chosen key, re-uploading this device's own keys) with the server passphrase, then
    ///   confirm. `.incomplete`: try restoring with it (another device may have applied it
    ///   already); otherwise `.needsRestoreLegacy` -- never reset from a locked device, it would
    ///   create secret storage without the cross-signing keys, and these JWT-only accounts can't
    ///   re-create cross-signing (no UIA flow).
    /// - Standard, active: restore silently if `.incomplete` -- on failure fall back to the
    ///   manual prompt, **never** reset, so a transient error can't wipe history.
    func ensureEncryption() async throws -> RecoveryPromptKind? {
        try await ensureClient()
        guard let enc = encryptionInfo, enc.isStandard, let passphrase = enc.passphrase else {
            return try await recoveryPromptKind()
        }
        let status = try await waitForRecoveryState()

        if enc.isPending {
            switch status {
            case .disabled:
                _ = try await setUpRecovery(passphrase: passphrase)
            case .enabled:
                _ = try await resetRecovery(passphrase: passphrase)
            default:
                do {
                    try await restoreRecovery(input: passphrase)
                } catch {
                    return .needsRestoreLegacy
                }
            }
            encryptionInfo = try await friendicaAPI().matrixEncryption(action: "confirm")
            return nil
        }

        switch status {
        case .incomplete:
            do {
                try await restoreRecovery(input: passphrase)
                return nil
            } catch {
                return .needsRestore
            }
        case .disabled:
            // Secret storage vanished server-side; recreate it under the same passphrase.
            _ = try await setUpRecovery(passphrase: passphrase)
            return nil
        default:
            return nil
        }
    }

    /// Standard -> private. Drops the server's copy only AFTER the rotation succeeded (the
    /// other order could leave the account behind a passphrase nobody has). Returns the key to
    /// show the user once.
    func switchToPrivate(passphrase: String?) async throws -> String {
        try await requireUnlocked()
        let key = try await resetRecovery(passphrase: passphrase)
        encryptionInfo = try await friendicaAPI().matrixEncryption(action: "set_private")
        return key
    }

    /// Private -> standard, with a brand-new server passphrase. If the reset fails after
    /// `prepare_standard`, the server stays pending and the next `ensureEncryption()` on any
    /// unlocked device finishes the switch.
    func switchToStandard() async throws {
        try await requireUnlocked()
        let api = try friendicaAPI()
        let enc = try await api.matrixEncryption(action: "prepare_standard")
        guard let passphrase = enc.passphrase else { throw MatrixError.malformedIdentity }
        _ = try await resetRecovery(passphrase: passphrase)
        encryptionInfo = try await api.matrixEncryption(action: "confirm")
    }

    private func requireUnlocked() async throws {
        try await ensureClient()
        guard try await waitForRecoveryState() == .enabled else { throw DeviceLockedError() }
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
    /// Bump to make every install discard its local Matrix session once more on its next chat
    /// login -- see `discardLocalSession(_:)`.
    private static let matrixSessionResetVersion = 1

    /// One-time local reset, run once per `matrixSessionResetVersion` bump on the first chat
    /// login after an app update. Version 1 = the move to standard chat encryption mode
    /// (2026-10): every account's old encryption identity was wiped server-side (larpnet-config
    /// `reset-chat-e2ee.sh`), but this app persists Matrix state locally and never sees deleted
    /// account data -- a phone that used chat before would keep its stale copy of the old secret
    /// storage and show the one-time "enter your old key" prompt.
    ///
    /// Same end state as logout's `clearSession()`: the old device is logged out server-side (one
    /// last JWT login to it, then `logout()` -- the only way to delete a device on these JWT-only
    /// accounts, which have no UIA flow for `DELETE /devices`), then the shared App Group store
    /// and the Keychain device id are discarded so `ensureClient()` continues as a brand-new
    /// device. The 60s JWT is reusable within its lifetime, so the fresh login right after still
    /// works. Best-effort on the server side: if that logout fails, the local reset still happens.
    /// Same policy as larpnet-android's `MatrixRepository.discardLocalSession()`.
    private func discardLocalSession(_ identity: MatrixLoginResponse) async {
        if let oldDeviceId = tokenStore.matrixDeviceId,
           let dir = try? MatrixSessionPaths.sessionDirectory(for: identity.userId),
           let old = try? await ClientBuilder()
               .homeserverUrl(url: identity.homeserver)
               .sessionPaths(dataPath: dir.path, cachePath: dir.path)
               .build() {
            if (try? await old.customLoginWithJwt(
                jwt: identity.token, initialDeviceName: "larpnet iOS", deviceId: oldDeviceId
            )) != nil {
                try? await old.logout()
            }
        }
        if let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: MatrixSessionPaths.appGroupIdentifier
        ) {
            try? FileManager.default.removeItem(at: base.appendingPathComponent("MatrixSession", isDirectory: true))
        }
        tokenStore.clearMatrixDeviceId()
    }

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

    // MARK: - Read receipts, unread counts, mute

    /// Synapse's own notification count for `room` (what every other client's badge shows; 0
    /// for a muted room, whose push rule has no `notify`). Not `numUnreadMessages`: that is
    /// computed from the SDK's event cache, which the plain v2 sync this app uses never fills,
    /// so it stayed 0 (same finding as larpnet-android, 2026-10-13).
    static func unreadCount(of room: Room) async -> Int {
        ((try? await room.roomInfo().notificationCount).map(Int.init)) ?? 0
    }

    /// The same name the room list shows for `roomId` -- for a thread opened from a
    /// notification, which only knows the room id.
    func roomDisplayName(roomId: String) async -> String? {
        guard let client = try? await ensureClient(), let room = try? client.getRoom(roomId: roomId) else { return nil }
        return await displayName(for: room)
    }

    /// Every muted room id -> when its mute ends (nil = permanent), read from local account
    /// data: the per-room override push rules in `m.push_rules` (what `larpnet_matrix_set_mute()`
    /// writes, and what Element/the Rust SDK call Mute -- a rule with no `notify` action), and
    /// the expiries in `pl.larpnet.mute_until`. Same rule as the server's
    /// `larpnet_matrix_list_mutes()` and the web client's `isRoomMuted()`.
    private func muteStates(_ client: Client) async -> [String: Date?] {
        guard
            let rulesJson = try? await client.accountData(eventType: "m.push_rules"),
            let rules = try? JSONSerialization.jsonObject(with: Data(rulesJson.utf8)) as? [String: Any],
            let overrides = (rules["global"] as? [String: Any])?["override"] as? [[String: Any]]
        else { return [:] }
        var expiries: [String: Any] = [:]
        if let json = try? await client.accountData(eventType: Self.muteAccountDataType),
           let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
           let rooms = object["rooms"] as? [String: Any] {
            expiries = rooms
        }

        var result: [String: Date?] = [:]
        for rule in overrides {
            guard let id = rule["rule_id"] as? String, id.hasPrefix("!") else { continue }
            if (rule["enabled"] as? Bool) == false { continue }
            let notifies = (rule["actions"] as? [Any])?.contains { ($0 as? String) == "notify" } ?? false
            if !notifies {
                result[id] = (expiries[id] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            }
        }
        return result
    }

    /// Muted state of one room, for the room info screen.
    func muteState(roomId: String) async -> (muted: Bool, until: Date?) {
        guard let client = try? await ensureClient() else { return (false, nil) }
        let mutes = await muteStates(client)
        return (mutes.keys.contains(roomId), mutes[roomId].flatMap { $0 })
    }

    /// Mutes `roomId` until `until` (nil = until unmuted) via `POST larpnet_matrix/mute`, and
    /// returns the server's updated mute map so the caller can show the change right away; the
    /// push rule itself arrives over sync shortly after.
    func muteRoom(roomId: String, until: Date?) async throws -> [String: Date?] {
        let millis = until.map { Int64($0.timeIntervalSince1970 * 1000) }
        return Self.dates(try await friendicaAPI().matrixMute(action: "mute", roomId: roomId, untilMillis: millis).mutes)
    }

    func unmuteRoom(roomId: String) async throws -> [String: Date?] {
        Self.dates(try await friendicaAPI().matrixMute(action: "unmute", roomId: roomId).mutes)
    }

    private static func dates(_ mutes: [String: Int64?]) -> [String: Date?] {
        mutes.mapValues { $0.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
    }

    private static let muteAccountDataType = "pl.larpnet.mute_until"

    /// Recomputes the unread-room count for `onUnreadCountChange`; skipped while one is already
    /// running (that one reads the latest state anyway).
    private func recountUnread(_ client: Client) async {
        guard !isRecountingUnread else { return }
        isRecountingUnread = true
        defer { isRecountingUnread = false }
        let mutes = await muteStates(client)
        var count = 0
        for room in client.rooms() where room.membership() == .joined && !mutes.keys.contains(room.id()) {
            if await Self.unreadCount(of: room) > 0 {
                count += 1
            }
        }
        onUnreadCountChange?(count)
    }

    /// Forces a fresh `/sync` round rather than waiting for the continuous `syncV2` loop's
    /// current long-poll to resolve on its own -- that loop pauses whenever iOS suspends this
    /// process, and nothing previously nudged it awake again, so a chat screen or room list
    /// opened right after a notification/foreground could sit on stale state until the loop
    /// happened to notice the backlog. Call on app resume (foreground, notification tap) and
    /// from a background remote-notification wake. Cancelling and re-subscribing `syncV2` is
    /// the same primitive `ensureClient()`/`startSyncLoop` already use, just re-triggered on
    /// demand -- the SDK's local since-token makes this a catch-up, not a full resync. No-op
    /// before the first `ensureClient()` login.
    func resyncNow() {
        guard let client else { return }
        startSyncLoop(client)
    }

    /// Async variant of `resyncNow()` for a background remote-notification wake: restarts the
    /// sync loop and gives it a short grace period to land a fresh round before returning, so
    /// `AppDelegate`'s `didReceiveRemoteNotification` can call iOS's fetch-completion handler
    /// promptly rather than either returning immediately (no catch-up actually happened yet) or
    /// holding the whole background budget open. Deliberately a fixed grace period, not a
    /// signal tied to the loop's own tick callback (`roomListContinuation`): that already has a
    /// single dedicated subscriber (the room list screen), and piggybacking a second waiter onto
    /// it risks dropping whichever one is currently listening.
    func resyncAndWait(graceSeconds: UInt64 = 5) async {
        guard client != nil else { return }
        resyncNow()
        try? await Task.sleep(nanoseconds: graceSeconds * 1_000_000_000)
    }

    // MARK: - Private

    private func startSyncLoop(_ client: Client) {
        syncHandle?.cancel()
        let bridge = SyncTickBridge { [weak self] in
            Task { @MainActor in
                self?.roomListContinuation?.yield()
                await self?.recountUnread(client)
            }
        }
        syncHandle = client.syncV2(settings: SyncSettingsV2(fullState: false), listener: bridge)
        Task { await recountUnread(client) }
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
    /// 1:1 DM, the partner's name via `resolvedName` (Friendica name first, so it also covers
    /// someone who's never opened chat themselves); for a group, its own name if it has one,
    /// else its members' resolved names -- not the SDK's computed name, which is built from the
    /// (here always empty, see `otherMemberIds(of:)`) heroes and so ends up as bare localparts.
    private func displayName(for room: Room) async -> String {
        let others = await otherMemberIds(of: room)
        if others.count == 1 {
            let peer = others[0]
            return resolvedName(userId: peer, fallbackDisplayName: try? await room.memberDisplayName(userId: peer))
        }
        if let raw = room.rawName(), !raw.isEmpty { return raw }
        if !others.isEmpty {
            // "Both" would read as a wall of "(@...)" in a joined list -- full names only there.
            let mode: ChatNameDisplay = ChatNameDisplay.current == .both ? .full : ChatNameDisplay.current
            var names: [String] = []
            for userId in others.prefix(3) {
                names.append(resolvedName(userId: userId, fallbackDisplayName: try? await room.memberDisplayName(userId: userId), mode: mode))
            }
            let joined = names.joined(separator: ", ")
            return others.count > 3 ? joined + " +\(others.count - 3)" : joined
        }
        if let name = room.displayName(), !name.isEmpty { return name }
        return "Chat"
    }

    /// Shared by the room-list hero name above and `roomInfo()`'s member list: prefer the
    /// Friendica name we already know (covers a member who's never opened chat themselves, so
    /// has no Matrix displayname yet) over the SDK-reported displayname, then fall back to the
    /// bare localpart.
    private func resolvedName(userId: String, fallbackDisplayName: String?, mode: ChatNameDisplay = .current) -> String {
        guard let localpart = Self.localpart(of: userId) else {
            if let name = fallbackDisplayName, !name.isEmpty { return name }
            return userId
        }
        let fullName: String
        if let resolved = contactsByLocalpart[localpart] {
            fullName = resolved
        } else if let name = fallbackDisplayName, !name.isEmpty {
            fullName = name
        } else {
            return localpart
        }
        switch mode {
        case .full: return fullName
        case .handle: return localpart
        case .both: return fullName.caseInsensitiveCompare(localpart) == .orderedSame ? fullName : "\(fullName) (@\(localpart))"
        }
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

    /// Read receipt for `eventId` (the newest message on screen). An explicit event id rather
    /// than `Timeline/Room.markAsRead`: both pick "newest event" from the SDK's event cache,
    /// which plain v2 sync never fills, so they silently sent nothing (confirmed on
    /// larpnet-android, 2026-10-13). Before this, no larpnet client sent receipts at all, so
    /// unread counts only cleared when another Matrix client marked the room read.
    func sendReadReceipt(eventId: String) async throws {
        try await timeline.sendReadReceipt(receiptType: .read, eventId: eventId)
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
            eventId: { if case .eventId(let id) = event.eventOrTransactionId { return id } else { return nil } }(),
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

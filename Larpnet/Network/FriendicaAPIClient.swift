import Foundation

/// Authenticated Mastodon-compatible API surface (Bearer token attached from `TokenStore` on
/// every call). Direct port of Android's `network/FriendicaApi.kt` -- endpoint coverage grows
/// phase by phase alongside the screens that need them; this file currently covers what
/// Phase 1 (OAuth spike) and Phase 3 (timelines) need. See the plan doc for the full 27-endpoint
/// list ported from Android.
///
/// On any 401/403, `forceLogout` is broadcast instead of retrying -- mirrors Android's
/// `AuthInterceptor`, which never retries and instead emits a one-shot event a top-level
/// screen collects to clear the token and navigate back to login.
final class FriendicaAPIClient: Sendable {
    let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    let forceLogout: AsyncStream<Void>
    private let forceLogoutContinuation: AsyncStream<Void>.Continuation

    init(baseURL: URL, session: URLSession, tokenStore: TokenStore) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
        var continuation: AsyncStream<Void>.Continuation!
        self.forceLogout = AsyncStream { continuation = $0 }
        self.forceLogoutContinuation = continuation
    }

    // MARK: - Accounts

    func verifyCredentials() async throws -> Account {
        try await send(path: "api/v1/accounts/verify_credentials")
    }

    func getAccount(id: String) async throws -> Account {
        try await send(path: "api/v1/accounts/\(id)")
    }

    func getAccountStatuses(id: String, maxId: String? = nil) async throws -> Page<Status> {
        var query: [URLQueryItem] = []
        if let maxId { query.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await sendPaged(path: "api/v1/accounts/\(id)/statuses", query: query)
    }

    func follow(id: String) async throws -> Relationship {
        try await send(path: "api/v1/accounts/\(id)/follow", method: "POST")
    }

    func unfollow(id: String) async throws -> Relationship {
        try await send(path: "api/v1/accounts/\(id)/unfollow", method: "POST")
    }

    func searchAccounts(query: String, limit: Int = 20, resolve: Bool = false) async throws -> [Account] {
        try await send(path: "api/v1/accounts/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "resolve", value: resolve ? "true" : "false"),
        ])
    }

    /// No Link-header pagination on this endpoint (Friendica's `Directory.php` just does
    /// `jsonExit`) -- callers page via a client-tracked `offset`, matching Android's
    /// `DirectoryViewModel`.
    func directory(offset: Int = 0, limit: Int = 40, order: String = "active", local: Bool = true) async throws -> [Account] {
        try await send(path: "api/v1/directory", query: [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "local", value: local ? "true" : "false"),
        ])
    }

    func relationships(ids: [String]) async throws -> [Relationship] {
        let query = ids.map { URLQueryItem(name: "id[]", value: $0) }
        return try await send(path: "api/v1/accounts/relationships", query: query)
    }

    func updateCredentials(
        displayName: String?, note: String?, locked: Bool?, discoverable: Bool?, bot: Bool?
    ) async throws -> Account {
        var fields: [String: String] = [:]
        if let displayName { fields["display_name"] = displayName }
        if let note { fields["note"] = note }
        if let locked { fields["locked"] = locked ? "true" : "false" }
        if let discoverable { fields["discoverable"] = discoverable ? "true" : "false" }
        if let bot { fields["bot"] = bot ? "true" : "false" }
        let request = try buildFormRequest(path: "api/v1/accounts/update_credentials", fields: fields, method: "PATCH")
        let (data, _) = try await perform(request)
        do {
            return try FriendicaJSON.decoder.decode(Account.self, from: data)
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
    }

    // MARK: - Notifications

    func notifications(maxId: String? = nil, sinceId: String? = nil) async throws -> Page<LarpnetNotification> {
        var query: [URLQueryItem] = []
        if let maxId { query.append(URLQueryItem(name: "max_id", value: maxId)) }
        if let sinceId { query.append(URLQueryItem(name: "since_id", value: sinceId)) }
        return try await sendPaged(path: "api/v1/notifications", query: query)
    }

    func clearNotifications() async throws {
        let request = try buildRequest(path: "api/v1/notifications/clear", method: "POST")
        _ = try await perform(request)
    }

    func dismissNotification(id: String) async throws {
        let request = try buildRequest(path: "api/v1/notifications/\(id)/dismiss", method: "POST")
        _ = try await perform(request)
    }

    // MARK: - Timelines

    func homeTimeline(maxId: String? = nil, sinceId: String? = nil, limit: Int = 40) async throws -> Page<Status> {
        try await sendPaged(path: "api/v1/timelines/home", query: pagingQuery(maxId: maxId, sinceId: sinceId, limit: limit))
    }

    func publicTimeline(
        maxId: String? = nil, sinceId: String? = nil, limit: Int = 40, local: Bool? = nil
    ) async throws -> Page<Status> {
        var query = pagingQuery(maxId: maxId, sinceId: sinceId, limit: limit)
        if let local {
            query.append(URLQueryItem(name: "local", value: local ? "true" : "false"))
        }
        return try await sendPaged(path: "api/v1/timelines/public", query: query)
    }

    // MARK: - Statuses

    func getStatus(id: String) async throws -> Status {
        try await send(path: "api/v1/statuses/\(id)")
    }

    func getContext(id: String) async throws -> StatusContext {
        try await send(path: "api/v1/statuses/\(id)/context")
    }

    func postStatus(
        status: String, inReplyToId: String? = nil, visibility: String = "public",
        spoilerText: String? = nil, sensitive: Bool? = nil, mediaIds: [String] = []
    ) async throws -> Status {
        var fields = ["status": status, "visibility": visibility]
        if let inReplyToId { fields["in_reply_to_id"] = inReplyToId }
        if let spoilerText { fields["spoiler_text"] = spoilerText }
        if let sensitive { fields["sensitive"] = sensitive ? "true" : "false" }
        let request = try buildFormRequest(
            path: "api/v1/statuses", fields: fields, arrayField: ("media_ids[]", mediaIds)
        )
        let (data, _) = try await perform(request)
        do {
            return try FriendicaJSON.decoder.decode(Status.self, from: data)
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
    }

    func deleteStatus(id: String) async throws {
        let request = try buildRequest(path: "api/v1/statuses/\(id)", method: "DELETE")
        _ = try await perform(request)
    }

    func favourite(id: String) async throws -> Status {
        try await send(path: "api/v1/statuses/\(id)/favourite", method: "POST")
    }

    func unfavourite(id: String) async throws -> Status {
        try await send(path: "api/v1/statuses/\(id)/unfavourite", method: "POST")
    }

    func reblog(id: String) async throws -> Status {
        try await send(path: "api/v1/statuses/\(id)/reblog", method: "POST")
    }

    func unreblog(id: String) async throws -> Status {
        try await send(path: "api/v1/statuses/\(id)/unreblog", method: "POST")
    }

    func bookmark(id: String) async throws -> Status {
        try await send(path: "api/v1/statuses/\(id)/bookmark", method: "POST")
    }

    func unbookmark(id: String) async throws -> Status {
        try await send(path: "api/v1/statuses/\(id)/unbookmark", method: "POST")
    }

    // MARK: - Conversations (DMs)
    //
    // GET/DELETE/read use the Mastodon-compatible `/api/v1/conversations` surface, which
    // reads/mutates Friendica's legacy `mail` table -- the same store the web UI's own
    // Messages uses. There is no Mastodon-API endpoint to *send* into that store
    // (`POST /api/v1/statuses?visibility=direct` is a fully separate, disconnected mechanism),
    // so sending and fetching one conversation's full message history go through the
    // Twitter-compat `/api/direct_messages` endpoints instead, which read/write the same
    // `mail` rows. Both surfaces share the same OAuth Bearer auth. Direct port of Android's
    // `FriendicaApi.kt` Conversations section -- see its doc comment for the full rationale.

    func conversations(maxId: String? = nil) async throws -> Page<Conversation> {
        var query: [URLQueryItem] = []
        if let maxId { query.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await sendPaged(path: "api/v1/conversations", query: query)
    }

    func markConversationRead(id: String) async throws -> Conversation {
        try await send(path: "api/v1/conversations/\(id)/read", method: "POST")
    }

    func deleteConversation(id: String) async throws {
        let request = try buildRequest(path: "api/v1/conversations/\(id)", method: "DELETE")
        _ = try await perform(request)
    }

    /// All messages exchanged with one contact (both directions), newest first,
    /// Link-header paginated.
    func directMessages(profileUrl: String, count: Int = 40, maxId: String? = nil) async throws -> Page<DirectMessage> {
        var query = [
            URLQueryItem(name: "profileurl", value: profileUrl),
            URLQueryItem(name: "count", value: String(count)),
        ]
        if let maxId { query.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await sendPaged(path: "api/direct_messages/all.json", query: query)
    }

    enum SendDirectMessageResult {
        case sent(DirectMessage)
        /// `NewDM.php`'s early guard only checks for `screen_name`/`user_id`, never
        /// `profileurl` -- and a failed send comes back as HTTP 200 with `{"error": N}` in the
        /// body, not a non-2xx status, so this must be checked explicitly rather than relying
        /// on `perform`'s status-code handling. Matches Android's documented workaround.
        case failed(errorCode: Int)
    }

    private struct DirectMessageErrorEnvelope: Decodable {
        let error: Int
    }

    func sendDirectMessage(screenName: String, text: String) async throws -> SendDirectMessageResult {
        let request = try buildFormRequest(
            path: "api/direct_messages/new.json",
            fields: ["screen_name": screenName, "text": text]
        )
        let (data, _) = try await perform(request)
        if let envelope = try? FriendicaJSON.decoder.decode(DirectMessageErrorEnvelope.self, from: data) {
            return .failed(errorCode: envelope.error)
        }
        do {
            return .sent(try FriendicaJSON.decoder.decode(DirectMessage.self, from: data))
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
    }

    // MARK: - Media

    func uploadMedia(data: Data, mimeType: String, filename: String, description: String? = nil) async throws -> MediaAttachment {
        guard let url = URL(string: "api/v1/media", relativeTo: baseURL) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        guard let token = tokenStore.accessToken else { throw NetworkError.notLoggedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = "larpnet-ios-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        if let description { appendField(name: "description", value: description) }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, _) = try await perform(request)
        do {
            return try FriendicaJSON.decoder.decode(MediaAttachment.self, from: responseData)
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
    }

    // MARK: - Request plumbing

    private func pagingQuery(maxId: String?, sinceId: String?, limit: Int) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        if let sinceId { items.append(URLQueryItem(name: "since_id", value: sinceId)) }
        return items
    }

    private func buildRequest(path: String, method: String = "GET", query: [URLQueryItem] = []) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        guard let token = tokenStore.accessToken else { throw NetworkError.notLoggedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func buildFormRequest(
        path: String, fields: [String: String], arrayField: (name: String, values: [String])? = nil,
        method: String = "POST"
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let token = tokenStore.accessToken else { throw NetworkError.notLoggedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var pairs = fields.map { key, value in "\(percentEncode(key))=\(percentEncode(value))" }
        if let arrayField {
            pairs += arrayField.values.map { "\(percentEncode(arrayField.name))=\(percentEncode($0))" }
        }
        request.httpBody = pairs.joined(separator: "&").data(using: .utf8)
        return request
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.network(underlying: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.network(underlying: "no HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            forceLogoutContinuation.yield(())
            throw NetworkError.auth
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return (data, http)
    }

    private func send<T: Decodable>(path: String, method: String = "GET", query: [URLQueryItem] = []) async throws -> T {
        let request = try buildRequest(path: path, method: method, query: query)
        let (data, _) = try await perform(request)
        do {
            return try FriendicaJSON.decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
    }

    private func sendPaged<T: Decodable & HasID>(path: String, query: [URLQueryItem] = []) async throws -> Page<T> {
        let request = try buildRequest(path: path, query: query)
        let (data, http) = try await perform(request)
        let items: [T]
        do {
            items = try FriendicaJSON.decoder.decode(LossyArray<T>.self, from: data).elements
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
        return LinkHeaderPaging.page(items: items, response: http)
    }
}

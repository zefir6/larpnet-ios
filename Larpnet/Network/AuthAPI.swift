import Foundation

/// Unauthenticated endpoints -- app registration and OAuth token exchange. Direct port of
/// Android's `network/AuthApi.kt`. Uses the same `session` (and therefore the same
/// `User-Agent`-carrying configuration) as the authenticated client; larpnet.pl's Cloudflare
/// WAF 403s any request missing that header regardless of whether it's an authenticated call.
struct AuthAPI: Sendable {
    let baseURL: URL
    let session: URLSession

    static let scope = "read write follow"

    func registerApp(clientName: String, redirectURI: String) async throws -> AppRegistration {
        try await postForm(
            path: "api/v1/apps",
            fields: [
                "client_name": clientName,
                "redirect_uris": redirectURI,
                "scopes": Self.scope,
            ]
        )
    }

    func exchangeToken(
        clientId: String, clientSecret: String, redirectURI: String, code: String
    ) async throws -> TokenResponse {
        try await postForm(
            path: "oauth/token",
            fields: [
                "client_id": clientId,
                "client_secret": clientSecret,
                "redirect_uri": redirectURI,
                "code": code,
                "grant_type": "authorization_code",
                "scope": Self.scope,
            ]
        )
    }

    private func postForm<T: Decodable>(path: String, fields: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&").data(using: .utf8)

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
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do {
            return try FriendicaJSON.decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
    }
}

private extension CharacterSet {
    /// Stricter than `.urlQueryAllowed` -- also escapes `&`/`=`/`+` so form field values
    /// containing those characters (unlikely here, but redirect URIs contain `:`/`/`) can't
    /// corrupt the `application/x-www-form-urlencoded` body.
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}

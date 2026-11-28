import Foundation

/// In-app account registration (friendica-larpnet's `Module\Api\Mastodon\LarpnetRegistration`).
/// Port of Android's `network/RegistrationApi.kt`. No user token yet, so every call carries the
/// app's OAuth `client_id`/`client_secret` (from `POST /api/v1/apps`, see `OAuthFlow`). Errors
/// are `{"error": "<code>", "error_description": "<message>"}`; the message language follows
/// `Accept-Language`, which URLSession sends from the device's preferred languages.
struct RegistrationAPI: Sendable {
    let baseURL: URL
    let session: URLSession

    struct Challenge: Decodable, Sendable {
        let challenge: String
    }

    struct Started: Decodable, Sendable {
        let id: String
        let email: String?
        let approvalRequired: Bool?

        enum CodingKeys: String, CodingKey {
            case id, email
            case approvalRequired = "approval_required"
        }
    }

    struct Confirmation: Decodable, Sendable {
        let status: String
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case status
            case accessToken = "access_token"
        }
    }

    /// The server's error body, plus the HTTP status.
    struct Failure: Error, Sendable {
        let status: Int
        let code: String
        let message: String?
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    func challenge(clientId: String, clientSecret: String) async throws -> Challenge {
        try await post("api/v1/larpnet/registration/challenge", ["client_id": clientId, "client_secret": clientSecret])
    }

    func register(fields: [String: String]) async throws -> Started {
        try await post("api/v1/accounts", fields)
    }

    func confirm(clientId: String, clientSecret: String, id: String, code: String) async throws -> Confirmation {
        try await post("api/v1/larpnet/registration/confirm", [
            "client_id": clientId, "client_secret": clientSecret, "id": id, "code": code,
        ])
    }

    func resend(clientId: String, clientSecret: String, id: String) async throws -> Confirmation {
        try await post("api/v1/larpnet/registration/resend", [
            "client_id": clientId, "client_secret": clientSecret, "id": id,
        ])
    }

    private func post<T: Decodable>(_ path: String, _ fields: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
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
            let body = try? FriendicaJSON.decoder.decode(ErrorBody.self, from: data)
            throw Failure(status: http.statusCode, code: body?.error ?? "", message: body?.errorDescription)
        }
        do {
            return try FriendicaJSON.decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.parse(underlying: String(describing: error))
        }
    }
}

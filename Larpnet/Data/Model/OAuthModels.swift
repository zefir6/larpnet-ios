import Foundation

/// Response of `POST /api/v1/apps`. Direct port of Android's `OAuthModels.kt` -- no
/// `website`/`vapid_key` fields since nothing in this app uses them (the server does emit
/// them; Swift's `Decodable` ignores unlisted keys by default, same effect as Kotlin's
/// `ignoreUnknownKeys`).
struct AppRegistration: Decodable, Sendable {
    let id: String
    let clientId: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case id
        case clientId = "client_id"
        case clientSecret = "client_secret"
    }
}

/// Response of `POST /oauth/token`. Deliberately has no `refreshToken`/`expiresIn` fields --
/// larpnet.pl never emits them (tokens don't expire server-side), matching Android's model.
struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

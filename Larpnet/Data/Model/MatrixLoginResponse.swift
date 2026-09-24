import Foundation

/// Response of `POST /larpnet_matrix` (`larpnet_matrix_post()`). `token` is a short-lived
/// (60s) JWT, traded for a real Matrix session via `Client.customLoginWithJwt` -- never
/// persisted, re-fetched fresh on every login (see `MatrixClientStore`).
struct MatrixLoginResponse: Decodable, Sendable {
    let userId: String
    let displayname: String
    let homeserver: String
    let loginType: String
    let token: String
    /// Nickname->displayname fallback for users who've never opened chat themselves (so have
    /// no Matrix displayname yet) -- same list the web client's `config.contacts` uses.
    let contacts: [MatrixContact]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayname
        case homeserver
        case loginType = "login_type"
        case token
        case contacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        displayname = try container.decode(String.self, forKey: .displayname)
        homeserver = try container.decode(String.self, forKey: .homeserver)
        loginType = try container.decode(String.self, forKey: .loginType)
        token = try container.decode(String.self, forKey: .token)
        // Tolerant: older server builds (before the contacts field shipped) omit this key.
        contacts = container.decode(.contacts, default: [])
    }
}

struct MatrixContact: Decodable, Sendable {
    let nickname: String
    let name: String
}

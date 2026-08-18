import Foundation

/// `GET /api/v1/preferences` is a read-only route on this server (`static/routes.config.php`
/// declares no write endpoint for any preferences field) -- direct port of Android's
/// `data/model/Preferences.kt`.
struct Preferences: Decodable, Sendable, Hashable {
    var postingDefaultLanguage: String?

    enum CodingKeys: String, CodingKey {
        case postingDefaultLanguage = "posting:default:language"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postingDefaultLanguage = try? c.decodeIfPresent(String.self, forKey: .postingDefaultLanguage)
    }
}

/// `GET /api/v1/larpnet_push_config` -- a larpnet-specific extension endpoint (not part of the
/// Mastodon API), the server-side counterpart of the ntfy-based browser push setup. Ported for
/// completeness/future use; **not called anywhere in v1** -- this app's background refresh
/// (see the Push module) polls `/api/v1/notifications` directly instead of relaying through
/// ntfy, since v1 has no long-lived background connection to hold open in the first place. See
/// the plan doc's "Push notifications" section for why this is a deliberate omission.
struct PushConfig: Decodable, Sendable, Hashable {
    var enabled: Bool
    var ntfyUrl: String?
    var ntfyTopic: String?
    var ntfyToken: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case ntfyUrl = "ntfy_url"
        case ntfyTopic = "ntfy_topic"
        case ntfyToken = "ntfy_token"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.decode(.enabled, default: false)
        ntfyUrl = try? c.decodeIfPresent(String.self, forKey: .ntfyUrl)
        ntfyTopic = try? c.decodeIfPresent(String.self, forKey: .ntfyTopic)
        ntfyToken = try? c.decodeIfPresent(String.self, forKey: .ntfyToken)
    }
}

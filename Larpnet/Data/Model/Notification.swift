import Foundation

/// Direct port of Android's `data/model/Notification.kt`. `type` is deliberately a raw
/// `String`, not an enum -- Friendica emits notification types beyond the standard Mastodon set
/// (e.g. "quote", "admin.*"), and decoding must not fail on one this app doesn't recognize.
struct LarpnetNotification: Decodable, Sendable, Hashable, HasID, Identifiable {
    var id: String
    var type: String
    var createdAt: Date
    var account: Account
    var status: Status?

    enum CodingKeys: String, CodingKey {
        case id, type, account, status
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = c.decode(.type, default: "unknown")
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        account = try c.decode(Account.self, forKey: .account)
        status = try? c.decodeIfPresent(Status.self, forKey: .status)
    }
}

import Foundation

/// Direct port of Android's `data/model/Conversation.kt`. Strictly 1:1 on this server --
/// Friendica's `mail` schema (which this endpoint reads/writes) has no multi-recipient support,
/// even though `accounts` is modeled as an array for Mastodon-API-shape compatibility.
struct Conversation: Decodable, Sendable, Hashable, HasID, Identifiable {
    var id: String
    var accounts: [Account]
    var unread: Bool
    var lastStatus: Status?

    enum CodingKeys: String, CodingKey {
        case id, accounts, unread
        case lastStatus = "last_status"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accounts = (try? c.decodeIfPresent(LossyArray<Account>.self, forKey: .accounts))??.elements ?? []
        unread = c.decode(.unread, default: false)
        lastStatus = try? c.decodeIfPresent(Status.self, forKey: .lastStatus)
    }
}

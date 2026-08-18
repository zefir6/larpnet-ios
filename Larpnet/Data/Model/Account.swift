import Foundation

/// Mirrors Android's `data/model/Account.kt`. Only `id` is guaranteed present/non-null; every
/// other field gets a `decodeIfPresent(...) ?? default` (see `JSONCoding.swift`) since
/// Friendica emits both nulls and, on some endpoints, omitted keys for fields Kotlin's
/// `@Serializable` defaults away silently.
struct Account: Decodable, Sendable, Hashable, HasID, Identifiable {
    var id: String
    var username: String
    var acct: String
    var displayName: String
    var avatar: String
    var url: String
    var note: String
    var locked: Bool
    var bot: Bool
    var discoverable: Bool
    var followersCount: Int
    var followingCount: Int
    var statusesCount: Int
    var header: String

    enum CodingKeys: String, CodingKey {
        case id, username, acct, url, note, locked, bot, discoverable, avatar, header
        case displayName = "display_name"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case statusesCount = "statuses_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = c.decode(.username, default: "")
        acct = c.decode(.acct, default: "")
        displayName = c.decode(.displayName, default: "")
        avatar = c.decode(.avatar, default: "")
        url = c.decode(.url, default: "")
        note = c.decode(.note, default: "")
        locked = c.decode(.locked, default: false)
        bot = c.decode(.bot, default: false)
        discoverable = c.decode(.discoverable, default: false)
        followersCount = c.decode(.followersCount, default: 0)
        followingCount = c.decode(.followingCount, default: 0)
        statusesCount = c.decode(.statusesCount, default: 0)
        header = c.decode(.header, default: "")
    }

    init(
        id: String, username: String = "", acct: String = "", displayName: String = "",
        avatar: String = "", url: String = "", note: String = "", locked: Bool = false,
        bot: Bool = false, discoverable: Bool = false, followersCount: Int = 0,
        followingCount: Int = 0, statusesCount: Int = 0, header: String = ""
    ) {
        self.id = id
        self.username = username
        self.acct = acct
        self.displayName = displayName
        self.avatar = avatar
        self.url = url
        self.note = note
        self.locked = locked
        self.bot = bot
        self.discoverable = discoverable
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.statusesCount = statusesCount
        self.header = header
    }
}

/// Mirrors Android's `Account.kt` companion `Relationship`.
struct Relationship: Decodable, Sendable, Hashable {
    var id: String
    var following: Bool
    var followedBy: Bool
    var blocking: Bool
    var muting: Bool
    var requested: Bool

    enum CodingKeys: String, CodingKey {
        case id, following, blocking, muting, requested
        case followedBy = "followed_by"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        following = c.decode(.following, default: false)
        followedBy = c.decode(.followedBy, default: false)
        blocking = c.decode(.blocking, default: false)
        muting = c.decode(.muting, default: false)
        requested = c.decode(.requested, default: false)
    }
}

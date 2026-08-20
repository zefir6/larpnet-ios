import Foundation

/// Class-backed box, used only to give `Status.reblog` finite storage size -- a `struct`
/// cannot store an `Optional<Self>` of itself directly (the Kotlin sibling has the same
/// problem in Rust's port of this API, which needed `Option<Box<Status>>` for the identical
/// reason). `Status` itself stays a value type so the optimistic favourite/reblog/bookmark
/// updates every timeline/thread/profile view model does (mutate a local copy before the
/// network call resolves) stay simple value-semantic assignments.
final class Box<Value: Sendable>: Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension Box: Equatable where Value: Equatable {
    static func == (lhs: Box, rhs: Box) -> Bool { lhs.value == rhs.value }
}

struct MediaAttachment: Decodable, Sendable, Hashable, Identifiable {
    var id: String
    var mediaType: String
    var url: String
    var previewUrl: String?
    var mediaDescription: String?

    enum CodingKeys: String, CodingKey {
        case id, url
        case mediaType = "type"
        case previewUrl = "preview_url"
        case mediaDescription = "description"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        mediaType = c.decode(.mediaType, default: "unknown")
        url = c.decode(.url, default: "")
        previewUrl = try? c.decodeIfPresent(String.self, forKey: .previewUrl)
        mediaDescription = try? c.decodeIfPresent(String.self, forKey: .mediaDescription)
    }
}

struct PollOption: Decodable, Sendable, Hashable {
    var title: String
    var votesCount: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case votesCount = "votes_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.decode(.title, default: "")
        votesCount = try? c.decodeIfPresent(Int.self, forKey: .votesCount)
    }
}

/// Read-only: poll voting is unimplemented server-side, same as Android -- the UI only ever
/// displays this, never submits votes.
struct Poll: Decodable, Sendable, Hashable {
    var id: String
    var expiresAt: Date?
    var expired: Bool
    var multiple: Bool
    var votesCount: Int
    var options: [PollOption]
    var voted: Bool

    enum CodingKeys: String, CodingKey {
        case id, expired, multiple, options, voted
        case expiresAt = "expires_at"
        case votesCount = "votes_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        expiresAt = try? c.decodeIfPresent(Date.self, forKey: .expiresAt)
        expired = c.decode(.expired, default: false)
        multiple = c.decode(.multiple, default: false)
        votesCount = c.decode(.votesCount, default: 0)
        options = (try? c.decodeIfPresent(LossyArray<PollOption>.self, forKey: .options))??.elements ?? []
        voted = c.decode(.voted, default: false)
    }
}

/// Mirrors Friendica's `Object\Api\Mastodon\Status` shape (verified live against
/// `larpnet.pl`'s `/api/v1/timelines/public`). Notable server-specific quirks, ported verbatim
/// from Android's doc comment since they're load-bearing, not obvious from the shape alone:
///  - `visibility` is only ever "public" | "private" | "unlisted" -- "direct" is never
///    emitted, even for DMs (those are surfaced via `/api/v1/conversations` instead).
///  - `spoilerText` is frequently just the post's title/subject, not a strict CW flag -- only
///    collapse content behind it when `sensitive == true`.
///  - `inReplyToAccountId` is the *thread root's* author, not the direct parent's -- don't
///    build "replying to @X" labels from it; resolve the parent via `ThreadBuilder` instead.
struct Status: Decodable, Sendable, Hashable, HasID, Identifiable {
    var id: String
    var createdAt: Date
    var content: String
    var spoilerText: String
    var sensitive: Bool
    var visibility: String
    var account: Account
    private var _reblog: Box<Status>?
    var inReplyToId: String?
    var inReplyToAccountId: String?
    var url: String?
    var mediaAttachments: [MediaAttachment]
    var poll: Poll?
    var favourited: Bool
    var reblogged: Bool
    var bookmarked: Bool
    var favouritesCount: Int
    var reblogsCount: Int
    var repliesCount: Int
    var language: String?

    var reblog: Status? {
        get { _reblog?.value }
        set { _reblog = newValue.map(Box.init) }
    }

    // Must compare full content, not just `id`: SwiftUI's `ForEach`/`LazyVStack` use
    // `Equatable` (when available) to decide whether a row actually needs to re-render, on top
    // of `Identifiable` just matching old/new elements up by id. An id-only `==` made every
    // optimistic favourite/reblog/bookmark update compare "equal" to the pre-toggle value, so
    // the row's `body` never re-ran and the tap silently produced no visible change -- confirmed
    // live by logging `StatusCard.body`'s entry: it fired once on initial layout and never again
    // after a toggle, even though the view model's own state had genuinely flipped.
    static func == (lhs: Status, rhs: Status) -> Bool {
        lhs.id == rhs.id && lhs.favourited == rhs.favourited && lhs.reblogged == rhs.reblogged
            && lhs.bookmarked == rhs.bookmarked && lhs.favouritesCount == rhs.favouritesCount
            && lhs.reblogsCount == rhs.reblogsCount && lhs.repliesCount == rhs.repliesCount
            && lhs.content == rhs.content && lhs.spoilerText == rhs.spoilerText
            && lhs.sensitive == rhs.sensitive && lhs._reblog == rhs._reblog
    }

    // Equal values (checked above) always share this hash -- the reverse isn't required for
    // `Hashable` correctness, so id-only hashing is still legal and keeps this cheap.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    enum CodingKeys: String, CodingKey {
        case id, content, sensitive, visibility, account, reblog, url, poll, favourited,
             reblogged, bookmarked, language
        case createdAt = "created_at"
        case spoilerText = "spoiler_text"
        case inReplyToId = "in_reply_to_id"
        case inReplyToAccountId = "in_reply_to_account_id"
        case mediaAttachments = "media_attachments"
        case favouritesCount = "favourites_count"
        case reblogsCount = "reblogs_count"
        case repliesCount = "replies_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        content = c.decode(.content, default: "")
        spoilerText = c.decode(.spoilerText, default: "")
        sensitive = c.decode(.sensitive, default: false)
        visibility = c.decode(.visibility, default: "public")
        account = try c.decode(Account.self, forKey: .account)
        let reblogValue = try? c.decodeIfPresent(Status.self, forKey: .reblog)
        _reblog = (reblogValue ?? nil).map(Box.init)
        inReplyToId = try? c.decodeIfPresent(String.self, forKey: .inReplyToId)
        inReplyToAccountId = try? c.decodeIfPresent(String.self, forKey: .inReplyToAccountId)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        mediaAttachments = (try? c.decodeIfPresent(LossyArray<MediaAttachment>.self, forKey: .mediaAttachments))??.elements ?? []
        poll = try? c.decodeIfPresent(Poll.self, forKey: .poll)
        favourited = c.decode(.favourited, default: false)
        reblogged = c.decode(.reblogged, default: false)
        bookmarked = c.decode(.bookmarked, default: false)
        favouritesCount = c.decode(.favouritesCount, default: 0)
        reblogsCount = c.decode(.reblogsCount, default: 0)
        repliesCount = c.decode(.repliesCount, default: 0)
        language = try? c.decodeIfPresent(String.self, forKey: .language)
    }

    init(
        id: String, createdAt: Date, content: String = "", spoilerText: String = "",
        sensitive: Bool = false, visibility: String = "public", account: Account,
        reblog: Status? = nil, inReplyToId: String? = nil, inReplyToAccountId: String? = nil,
        url: String? = nil, mediaAttachments: [MediaAttachment] = [], poll: Poll? = nil,
        favourited: Bool = false, reblogged: Bool = false, bookmarked: Bool = false,
        favouritesCount: Int = 0, reblogsCount: Int = 0, repliesCount: Int = 0,
        language: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
        self.spoilerText = spoilerText
        self.sensitive = sensitive
        self.visibility = visibility
        self.account = account
        self._reblog = reblog.map(Box.init)
        self.inReplyToId = inReplyToId
        self.inReplyToAccountId = inReplyToAccountId
        self.url = url
        self.mediaAttachments = mediaAttachments
        self.poll = poll
        self.favourited = favourited
        self.reblogged = reblogged
        self.bookmarked = bookmarked
        self.favouritesCount = favouritesCount
        self.reblogsCount = reblogsCount
        self.repliesCount = repliesCount
        self.language = language
    }
}

struct StatusContext: Decodable, Sendable {
    var ancestors: [Status]
    var descendants: [Status]

    enum CodingKeys: String, CodingKey {
        case ancestors, descendants
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ancestors = (try? c.decodeIfPresent(LossyArray<Status>.self, forKey: .ancestors))??.elements ?? []
        descendants = (try? c.decodeIfPresent(LossyArray<Status>.self, forKey: .descendants))??.elements ?? []
    }
}

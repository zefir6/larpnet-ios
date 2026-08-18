import Foundation

/// Twitter-compat shape (`/api/direct_messages/*`), used because there is no Mastodon-API route
/// to *send* into Friendica's `mail` table (see `FriendicaAPIClient` doc comments once the
/// Conversations/Messages endpoints are ported in a later phase). Direct port of Android's
/// `data/model/DirectMessage.kt`.
///
/// Two landmines specific to this model, both load-bearing:
///  - `createdAt` is intentionally kept as a raw `String`, not `Date` -- this endpoint emits
///    Twitter's legacy format (`"EEE MMM d HH:mm:ss Z yyyy"`), not ISO 8601 like every other
///    endpoint. Parse it with `Self.parseTwitterDate` at the UI layer, not here, matching
///    Android's `parseTwitterDate`.
///  - `error` must be checked by callers of `sendDirectMessage` -- a failed send comes back as
///    HTTP 200 with `{"error": N}` in the body instead of a non-2xx status, so decoding this
///    struct successfully does *not* mean the send succeeded.
struct DirectMessage: Decodable, Sendable, Hashable, HasID, Identifiable {
    var id: String
    var senderId: String
    var recipientId: String
    var text: String
    var createdAt: String
    var senderScreenName: String
    var recipientScreenName: String
    var seen: Bool
    var error: Int?

    enum CodingKeys: String, CodingKey {
        case id, text, error
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case createdAt = "created_at"
        case senderScreenName = "sender_screen_name"
        case recipientScreenName = "recipient_screen_name"
        case seen = "friendica_seen"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        senderId = c.decode(.senderId, default: "")
        recipientId = c.decode(.recipientId, default: "")
        text = c.decode(.text, default: "")
        createdAt = c.decode(.createdAt, default: "")
        senderScreenName = c.decode(.senderScreenName, default: "")
        recipientScreenName = c.decode(.recipientScreenName, default: "")
        // `friendica_seen` is emitted as 0/1, not a JSON bool, on some server versions --
        // decode via Int fallback the same way Android's Kotlin model tolerates both shapes.
        if let boolValue = try? c.decodeIfPresent(Bool.self, forKey: .seen) {
            seen = boolValue
        } else {
            seen = (try? c.decodeIfPresent(Int.self, forKey: .seen)) == 1
        }
        error = try? c.decodeIfPresent(Int.self, forKey: .error)
    }

    private static let twitterDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d HH:mm:ss Z yyyy"
        return f
    }()

    /// Parses `createdAt`'s Twitter-legacy format. Returns `nil` (rather than "now") on
    /// failure so callers can decide how to degrade, matching Android's `parseTwitterDate`.
    var parsedCreatedAt: Date? {
        Self.twitterDateFormatter.date(from: createdAt)
    }
}

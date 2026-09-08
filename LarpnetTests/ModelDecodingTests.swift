import XCTest
@testable import Larpnet

/// Proves the landmine-aware `Decodable` implementations in `Data/Model/` actually absorb
/// Friendica's JSON quirks (nulls-for-defaulted-fields, missing keys, non-ISO8601 dates) rather
/// than merely assuming Kotlin's `coerceInputValues`/`ignoreUnknownKeys` behavior transfers for
/// free. `status_public_live.json` is a verbatim capture of a real
/// `GET /api/v1/timelines/public` response from `larpnet.pl`; the others are constructed from
/// the documented API shapes (see each model's doc comment) since the notifications/
/// conversations/DM endpoints require an authenticated session this test suite doesn't have.
final class ModelDecodingTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture: \(name).json")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    func testDecodesRealPublicTimelineStatus() throws {
        let data = try loadFixture("status_public_live")
        let status = try FriendicaJSON.decoder.decode(Status.self, from: data)
        XCTAssertEqual(status.id, "244861")
        XCTAssertEqual(status.visibility, "public")
        XCTAssertEqual(status.account.acct, "robindlaws@dice.camp")
        XCTAssertEqual(status.account.followersCount, 3251)
        XCTAssertNil(status.reblog)
        XCTAssertTrue(status.content.contains("Ken and Robin"))
        // "2026-08-18T12:30:24.000Z" -- fractional-seconds ISO 8601, the exact shape that
        // trips up `JSONDecoder.DateDecodingStrategy.iso8601`.
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(status.createdAt, expected.date(from: "2026-08-18T12:30:24.000Z"))
    }

    func testDecodesStatusTags() throws {
        let data = try loadFixture("status_with_tags")
        let status = try FriendicaJSON.decoder.decode(Status.self, from: data)
        XCTAssertEqual(status.tags.map(\.name), ["larp", "warsaw"])
        XCTAssertEqual(status.tags.map(\.url), ["https://larpnet.pl/tag/larp", "https://larpnet.pl/tag/warsaw"])
    }

    func testDecodesStatusWithNullsAndMissingKeys() throws {
        let data = try loadFixture("status_nulls_and_missing")
        let status = try FriendicaJSON.decoder.decode(Status.self, from: data)
        XCTAssertEqual(status.id, "999001")
        XCTAssertEqual(status.content, "", "explicit JSON null on a defaulted field must fall back, not throw")
        XCTAssertEqual(status.spoilerText, "")
        XCTAssertEqual(status.visibility, "public", "missing/null visibility should default like Android's model")
        XCTAssertFalse(status.sensitive)
        XCTAssertNil(status.reblog)
        XCTAssertNil(status.poll)
        XCTAssertEqual(status.mediaAttachments, [])
        XCTAssertEqual(status.favouritesCount, 0, "omitted key must default, not throw")
        XCTAssertEqual(status.account.id, "42")
        XCTAssertEqual(status.account.username, "", "nested Account also only guarantees id")
    }

    func testDecodesPartialAccount() throws {
        let data = try loadFixture("account_partial")
        let account = try FriendicaJSON.decoder.decode(Account.self, from: data)
        XCTAssertEqual(account.id, "7")
        XCTAssertEqual(account.username, "testuser")
        XCTAssertEqual(account.displayName, "", "explicit null on display_name must fall back")
        XCTAssertFalse(account.locked, "explicit null on locked must fall back")
        XCTAssertEqual(account.note, "", "missing key must default")
    }

    func testDecodesNotificationWithStatus() throws {
        let data = try loadFixture("notification_mention")
        let notification = try FriendicaJSON.decoder.decode(LarpnetNotification.self, from: data)
        XCTAssertEqual(notification.type, "mention")
        XCTAssertEqual(notification.account.acct, "robindlaws@dice.camp")
        XCTAssertEqual(notification.status?.id, "244861")
    }

    func testDecodesNotificationWithUnrecognizedType() throws {
        // Friendica emits notification types beyond the standard Mastodon set -- decoding
        // must not fail just because this app doesn't recognize "admin.report".
        let data = try loadFixture("notification_unknown_type")
        let notification = try FriendicaJSON.decoder.decode(LarpnetNotification.self, from: data)
        XCTAssertEqual(notification.type, "admin.report")
    }

    func testDecodesConversation() throws {
        let data = try loadFixture("conversation")
        let conversation = try FriendicaJSON.decoder.decode(Conversation.self, from: data)
        XCTAssertTrue(conversation.unread)
        XCTAssertEqual(conversation.accounts.first?.id, "12")
        XCTAssertEqual(conversation.lastStatus?.content, "<p>hi there</p>")
    }

    func testDecodesDirectMessageWithTwitterDate() throws {
        let data = try loadFixture("direct_message")
        let message = try FriendicaJSON.decoder.decode(DirectMessage.self, from: data)
        XCTAssertEqual(message.text, "see you at the larp")
        XCTAssertFalse(message.seen, "friendica_seen: 0 must decode as false")
        XCTAssertNil(message.error)
        XCTAssertNotNil(message.parsedCreatedAt, "Twitter-format created_at must parse via the dedicated formatter")
    }

    func testSendDirectMessageErrorEnvelopeIsNotAValidMessage() throws {
        // Documents the trap: a failed send comes back as HTTP 200 with `{"error": N}` --
        // decoding it as a `DirectMessage` must fail (no `id`) so a real repository
        // implementation is forced to check for this envelope before assuming success.
        let data = try loadFixture("direct_message_send_error")
        XCTAssertThrowsError(try FriendicaJSON.decoder.decode(DirectMessage.self, from: data))

        struct ErrorEnvelope: Decodable { let error: Int }
        let envelope = try FriendicaJSON.decoder.decode(ErrorEnvelope.self, from: data)
        XCTAssertEqual(envelope.error, 1)
    }

    func testDecodesCirclesAndFiltersOutNonNumericChannels() throws {
        // Verbatim capture of a real `GET /api/v1/lists` response from `larpnet.pl` -- includes
        // both real circles (numeric id, postable via `visibility=<id>`) and Mastodon "channel"
        // pseudo-lists (`channel:foryou` etc.), which aren't real circles and must be filtered
        // out before offering them as a custom-audience option (see `FriendicaCircle`'s doc
        // comment and `FriendicaAPIClient.circles()`).
        let data = try loadFixture("lists_live")
        let all = try FriendicaJSON.decoder.decode([FriendicaCircle].self, from: data)
        XCTAssertEqual(all.count, 4)
        let postable = all.filter { Int($0.id) != nil }
        XCTAssertEqual(postable.map(\.id), ["160", "161"])
        XCTAssertEqual(postable.map(\.title), ["Friends", "Groups"])
    }
}

import XCTest
@testable import Larpnet

/// Covers the `static`, host-independent parsing halves of `LocalPostFilterStore` and
/// `FollowedThreadsStore` -- kept static specifically so these are testable without touching
/// `UserDefaults.standard`, which `TokenStore` hardcodes.
final class LocalPersistenceStoreTests: XCTestCase {
    func testLocalPostFilterStoreParsesCommaJoinedIds() {
        XCTAssertEqual(LocalPostFilterStore.parse("3,2,1"), ["3", "2", "1"])
    }

    func testLocalPostFilterStoreParseHandlesNilAndEmpty() {
        XCTAssertEqual(LocalPostFilterStore.parse(nil), [])
        XCTAssertEqual(LocalPostFilterStore.parse(""), [])
    }

    func testLocalPostFilterStoreParseDropsEmptyEntries() {
        // A trailing/leading comma (e.g. from a manually-edited default) shouldn't produce an
        // empty-string id that would then vacuously match nothing but bloat the list.
        XCTAssertEqual(LocalPostFilterStore.parse(",3,,2,"), ["3", "2"])
    }

    func testFollowedThreadsStoreRoundTripsThroughJSON() {
        let original = [
            FollowedThread(rootStatusId: "10", lastSeenReplyCount: 2, followedAt: 100),
            FollowedThread(rootStatusId: "20", lastSeenReplyCount: 0, followedAt: 200),
        ]
        let data = try! JSONEncoder().encode(original)
        let raw = String(data: data, encoding: .utf8)
        XCTAssertEqual(FollowedThreadsStore.parse(raw), original)
    }

    func testFollowedThreadsStoreParseHandlesNilAndGarbage() {
        XCTAssertEqual(FollowedThreadsStore.parse(nil), [])
        XCTAssertEqual(FollowedThreadsStore.parse("not json"), [])
    }
}

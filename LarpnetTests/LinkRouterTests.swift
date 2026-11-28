import XCTest
@testable import Larpnet

final class LinkRouterTests: XCTestCase {
    private func route(_ string: String) -> LinkTarget {
        LinkRouter.classify(URL(string: string)!, instanceHost: "larpnet.pl")
    }

    func testOwnPostsAndProfiles() {
        XCTAssertEqual(route("https://larpnet.pl/display/abc-123"), .resolve("https://larpnet.pl/display/abc-123"))
        XCTAssertEqual(route("https://larpnet.pl/profile/zefir"), .localProfile(nickname: "zefir"))
        XCTAssertEqual(route("https://larpnet.pl/@zefir"), .localProfile(nickname: "zefir"))
        XCTAssertEqual(route("https://larpnet.pl/search?tag=larp"), .hashtag("larp"))
        XCTAssertEqual(route("https://larpnet.pl/calendar"), .instancePage(URL(string: "https://larpnet.pl/calendar")))
    }

    func testFediverseLinks() {
        for url in [
            "https://mastodon.social/@Gargron",
            "https://mastodon.social/@Gargron/113000000000000000",
            "https://mastodon.social/users/Gargron/statuses/113000000000000000",
            "https://friendica.example/display/0123abcd",
            "https://pleroma.example/notice/AbCd123",
            "https://misskey.example/notes/9xyz",
            "https://lemmy.example/post/42",
        ] {
            XCTAssertEqual(route(url), .resolve(url), url)
        }
        XCTAssertEqual(route("https://mastodon.social/tags/larp"), .hashtag("larp"))
    }

    func testOrdinaryLinksGoToTheBrowser() {
        XCTAssertEqual(route("https://example.com/blog/2026/11/hello"), .external(URL(string: "https://example.com/blog/2026/11/hello")!))
        XCTAssertEqual(route("mailto:a@b.pl"), .external(URL(string: "mailto:a@b.pl")!))
    }

    func testMastodonProtocol() {
        XCTAssertEqual(route("web+mastodon://follow?uri=acct:Gargron@mastodon.social"), .resolve("Gargron@mastodon.social"))
        XCTAssertEqual(route("web+mastodon://follow?uri=%40Gargron%40mastodon.social"), .resolve("Gargron@mastodon.social"))
        XCTAssertEqual(route("web+mastodon://share?text=Hello%20world&url=https%3A%2F%2Fx.pl"), .share("Hello world https://x.pl"))
    }

    func testWebAp() {
        XCTAssertEqual(route("web+ap://mastodon.social/users/Gargron"), .resolve("https://mastodon.social/users/Gargron"))
        XCTAssertEqual(route("web+ap://example.com/ap/object/1"), .resolve("https://example.com/ap/object/1"))
    }

    func testWebsiteBanner() {
        XCTAssertEqual(route("larpnet://open?url=https%3A%2F%2Flarpnet.pl%2Fdisplay%2Fabc"), .resolve("https://larpnet.pl/display/abc"))
        XCTAssertEqual(route("larpnet://open?url=https%3A%2F%2Flarpnet.pl%2Fnetwork"), .instancePage(URL(string: "https://larpnet.pl/network")))
        XCTAssertEqual(route("larpnet://open"), .instancePage(nil))
    }

    func testHandles() {
        XCTAssertTrue(LinkRouter.isHandle("Gargron@mastodon.social"))
        XCTAssertFalse(LinkRouter.isHandle("https://mastodon.social/@Gargron"))
    }
}

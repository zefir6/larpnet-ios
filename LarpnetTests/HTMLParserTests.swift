import XCTest
@testable import Larpnet

/// `HTMLParser.plainText` backs the Notifications preview -- proves it collapses a real
/// multi-paragraph post (the exact shape that broke notification previews: several `<p>`
/// blocks plus an `<span class="h-card">` mention) into one flat string with paragraph
/// boundaries turned into whitespace, not run together or left with stray markup.
final class HTMLParserTests: XCTestCase {
    func testPlainTextCollapsesParagraphsAndStripsMentionMarkup() {
        let html = """
        <p>First paragraph with a <span class="h-card"><a href="https://larpnet.pl/profile/savil" \
        class="u-url mention">@<span>savil</span></a></span> mention.</p>\
        <p>Second paragraph.</p>
        """
        let text = HTMLParser.plainText(html)
        XCTAssertFalse(text.contains("<"), "no HTML tags should survive")
        XCTAssertTrue(text.contains("First paragraph"))
        XCTAssertTrue(text.contains("Second paragraph"))
        XCTAssertTrue(text.contains("@savil"))
        XCTAssertFalse(
            text.contains("mention.Second"), "paragraph boundary must become whitespace, not run words together"
        )
    }

    func testPlainTextOfEmptyStringIsEmpty() {
        XCTAssertEqual(HTMLParser.plainText(""), "")
    }
}

import Foundation
import SwiftSoup

/// Turns a post's raw HTML `content` into a small block-level tree, direct port of Android's
/// `domain/html/HtmlParser.kt`. Friendica's HTML is richer than plain Mastodon text (images,
/// blockquotes, lists, code), and a `WKWebView`-per-post wouldn't scale in a timeline, so this
/// renders natively via `HTMLContentView` instead.
///
/// Sanitization uses SwiftSoup's `Whitelist` (the Jsoup analogue Android's `Safelist.none()`
/// allow-list is ported from 1:1): only `p, br, a, span, strong, b, em, i, u, s, del, ul, ol,
/// li, blockquote, code, pre, img, h1-h4`, with `href`/`src`/`alt` attributes and `http`/`https`
/// protocols only.
///
/// The block/inline split is the load-bearing fix Android needed for a real federated post
/// whose body was a run of bare `#hashtag` links directly under `<body>`, not wrapped in a
/// `<p>` -- treating every top-level node as its own block would render one hashtag per line
/// instead of one flowing paragraph. `parseSiblings` instead buffers consecutive non-block
/// siblings (text, `<a>`, `<span>`, etc.) and only starts a new block on an actual block-level
/// tag, flushing the buffer as one `Paragraph` first.
enum HTMLParser {
    private static let blockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "blockquote", "pre", "code", "ul", "ol", "img",
    ]

    private static func makeWhitelist() throws -> Whitelist {
        let whitelist = Whitelist.none()
        try whitelist.addTags(
            "p", "br", "a", "span", "strong", "b", "em", "i", "u", "s", "del",
            "ul", "ol", "li", "blockquote", "code", "pre", "img", "h1", "h2", "h3", "h4"
        )
        try whitelist.addAttributes("a", "href")
        try whitelist.addAttributes("img", "src", "alt")
        try whitelist.addProtocols("a", "href", "http", "https")
        try whitelist.addProtocols("img", "src", "http", "https")
        return whitelist
    }

    static func parse(_ rawHTML: String) -> [HTMLNode] {
        guard !rawHTML.isEmpty else { return [] }
        do {
            let cleaned = try SwiftSoup.clean(rawHTML, makeWhitelist()) ?? ""
            let document = try SwiftSoup.parseBodyFragment(cleaned)
            guard let body = document.body() else { return [] }
            return parseSiblings(body.getChildNodes())
        } catch {
            // Sanitizer/parser failure on genuinely malformed input -- degrade to plain text
            // rather than dropping the post silently.
            return [.paragraph(AttributedString(rawHTML))]
        }
    }

    private static func parseSiblings(_ nodes: [Node]) -> [HTMLNode] {
        var result: [HTMLNode] = []
        var inlineBuffer: [Node] = []

        func flushInline() {
            guard !inlineBuffer.isEmpty else { return }
            let text = inlineNodesToAttributedString(inlineBuffer)
            inlineBuffer.removeAll()
            if !String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.paragraph(text))
            }
        }

        for node in nodes {
            if let element = node as? Element, blockTags.contains(element.tagName().lowercased()) {
                flushInline()
                result.append(contentsOf: parseBlockElement(element))
            } else {
                inlineBuffer.append(node)
            }
        }
        flushInline()
        return result
    }

    private static func parseBlockElement(_ element: Element) -> [HTMLNode] {
        let tag = element.tagName().lowercased()
        switch tag {
        case "p", "h1", "h2", "h3", "h4":
            let text = inlineNodesToAttributedString(element.getChildNodes())
            return String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.paragraph(text)]
        case "img":
            let src = (try? element.attr("src")) ?? ""
            guard !src.isEmpty else { return [] }
            let alt = (try? element.attr("alt")) ?? ""
            return [.image(url: src, description: alt.isEmpty ? nil : alt)]
        case "blockquote":
            return [.blockquote(parseSiblings(element.getChildNodes()))]
        case "pre", "code":
            let text = (try? element.text(trimAndNormaliseWhitespace: false)) ?? ""
            return [.codeBlock(text)]
        case "ul", "ol":
            let items = element.children()
                .filter { $0.tagName().lowercased() == "li" }
                .map { inlineNodesToAttributedString($0.getChildNodes()) }
            return [.list(items: items, ordered: tag == "ol")]
        default:
            // Transparent container -- recurse into its children as if they were siblings.
            return parseSiblings(element.getChildNodes())
        }
    }

    // MARK: - Inline walk

    private static func inlineNodesToAttributedString(_ nodes: [Node]) -> AttributedString {
        var result = AttributedString()
        for node in nodes {
            result += inlineNodeToAttributedString(node)
        }
        return result
    }

    private static func inlineNodeToAttributedString(_ node: Node) -> AttributedString {
        if let textNode = node as? TextNode {
            return AttributedString(textNode.text())
        }
        guard let element = node as? Element else {
            return AttributedString()
        }
        let tag = element.tagName().lowercased()
        if tag == "br" {
            return AttributedString("\n")
        }

        var children = inlineNodesToAttributedString(element.getChildNodes())
        switch tag {
        case "strong", "b":
            merge(.stronglyEmphasized, into: &children)
        case "em", "i":
            merge(.emphasized, into: &children)
        case "s", "del":
            merge(.strikethrough, into: &children)
        case "u":
            children.underlineStyle = .single
        case "a":
            if let href = try? element.attr("href"), let url = URL(string: href) {
                children.link = url
            }
        default:
            break
        }
        return children
    }

    /// `InlinePresentationIntent` is an `OptionSet` -- a plain assignment on the whole run
    /// would clobber an intent already set by an enclosing/nested tag (e.g. `<strong><em>`),
    /// so this merges per existing run instead.
    private static func merge(_ intent: InlinePresentationIntent, into text: inout AttributedString) {
        for run in text.runs {
            var existing = text[run.range].inlinePresentationIntent ?? []
            existing.insert(intent)
            text[run.range].inlinePresentationIntent = existing
        }
    }
}

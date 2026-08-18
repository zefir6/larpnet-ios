import Foundation

/// Block-level tree produced by `HTMLParser`. Direct port of Android's
/// `domain/html/HtmlNode.kt` sealed interface -- inline formatting (bold/italic/links/etc.) is
/// resolved eagerly into `AttributedString` at parse time rather than kept as a separate inline
/// tree, matching the Kotlin original's use of `AnnotatedString`.
enum HTMLNode: Equatable {
    case paragraph(AttributedString)
    case image(url: String, description: String?)
    indirect case blockquote([HTMLNode])
    case codeBlock(String)
    case list(items: [AttributedString], ordered: Bool)
}

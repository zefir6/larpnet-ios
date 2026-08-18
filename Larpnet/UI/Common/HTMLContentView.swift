import SwiftUI

/// Renders the `[HTMLNode]` block tree produced by `HTMLParser` -- the native-rendering
/// counterpart of Android's `ui/common/HtmlContent.kt` (a `WKWebView`-per-post wouldn't scale
/// in a timeline).
struct HTMLContentView: View {
    let nodes: [HTMLNode]

    init(html: String) {
        self.nodes = HTMLParser.parse(html)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                HTMLNodeView(node: node)
            }
        }
    }
}

private struct HTMLNodeView: View {
    let node: HTMLNode

    var body: some View {
        switch node {
        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .image(let url, let description):
            RemoteImage(url: URL(string: url))
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .accessibilityLabel(description ?? "")
        case .blockquote(let children):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    HTMLNodeView(node: child)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
            }
        case .codeBlock(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(.secondary)
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

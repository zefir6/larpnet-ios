import Foundation

/// One page of a Link-header-paginated list endpoint. Direct port of Android's
/// `network/LinkHeaderPaging.kt`.
struct Page<Element> {
    var items: [Element]
    var nextMaxId: String?
    var prevMinId: String?
}

enum LinkHeaderPaging {
    /// Parses the Mastodon-style `Link` response header (`rel="next"`/`rel="prev"`, each
    /// carrying a `max_id`/`min_id`/`since_id` query param) rather than the JSON body, which
    /// carries no pagination info on this server. Falls back to the last item's id (via
    /// `HasID`) as `nextMaxId` if the header is absent -- some endpoints (directory, account
    /// search) have no Link header at all and page by a client-tracked offset instead; this
    /// fallback is defense in depth for endpoints that normally have one but sent zero items.
    static func page<T: HasID>(items: [T], response: HTTPURLResponse) -> Page<T> {
        var nextMaxId: String?
        var prevMinId: String?

        if let linkHeader = response.value(forHTTPHeaderField: "Link") {
            for entry in linkHeader.components(separatedBy: ",") {
                let parts = entry.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let urlPart = parts.first,
                      urlPart.hasPrefix("<"), urlPart.hasSuffix(">") else { continue }
                let urlString = String(urlPart.dropFirst().dropLast())
                guard let comps = URLComponents(string: urlString) else { continue }
                let rel = parts.dropFirst().first { $0.hasPrefix("rel=") }?
                    .replacingOccurrences(of: "rel=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let queryItems = comps.queryItems ?? []
                if rel == "next" {
                    nextMaxId = queryItems.first { $0.name == "max_id" }?.value
                } else if rel == "prev" {
                    prevMinId = queryItems.first { $0.name == "min_id" }?.value
                        ?? queryItems.first { $0.name == "since_id" }?.value
                }
            }
        }

        if nextMaxId == nil {
            nextMaxId = items.last?.id
        }

        return Page(items: items, nextMaxId: nextMaxId, prevMinId: prevMinId)
    }
}

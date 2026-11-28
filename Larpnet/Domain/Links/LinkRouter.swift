import Foundation

/// Where a tapped or incoming link should go. See `LinkRouter.classify`.
enum LinkTarget: Equatable {
    /// A hashtag timeline.
    case hashtag(String)
    /// A local account by nickname (`larpnet.pl/profile/<nick>`).
    case localProfile(nickname: String)
    /// A post or account somewhere in the fediverse (an http(s) URL or a `user@host` handle),
    /// resolved through the server's `api/v2/search?resolve=true`.
    case resolve(String)
    /// `web+mastodon://share?text=...`: a new post prefilled with this text.
    case share(String)
    /// A page of our own instance the app has no screen for (settings, events...).
    case instancePage(URL?)
    /// Anything else: the browser.
    case external(URL)
}

/// Decides what a link means for the app -- pure, unit tested in `LinkRouterTests`. Same rules
/// as larpnet-android's `domain/links/LinkRouter.kt`.
///
/// Handles links tapped inside posts and links the app is opened with: `https://larpnet.pl/...`
/// Universal Links, `larpnet://open?url=<page>` from the website's "Open in app" banner, and
/// the `web+mastodon://` (Mastodon's protocol handler) and `web+ap://` (FEP-07d7, ActivityPub
/// objects) schemes.
enum LinkRouter {
    // Path shapes of posts and profiles on the common fediverse servers: Mastodon (/@user,
    // /@user/123, /users/user, /users/user/statuses/123), Friendica (/profile/x, /display/guid),
    // Pleroma/Akkoma (/notice/id, /objects/uuid), Misskey (/notes/id), Pixelfed (/p/user/id),
    // Lemmy (/post/id, /u/user, /c/community), GoToSocial (/@user/statuses/id).
    private static let fediversePaths = [
        #"^/@[^/]+/?$"#,
        #"^/@[^/]+/(statuses/)?[A-Za-z0-9_-]+/?$"#,
        #"^/users/[^/]+/?$"#,
        #"^/users/[^/]+/statuses/[A-Za-z0-9_-]+/?$"#,
        #"^/profile/[^/]+/?$"#,
        #"^/display/[A-Za-z0-9_-]+/?$"#,
        #"^/notice/[A-Za-z0-9_-]+/?$"#,
        #"^/objects/[A-Za-z0-9_-]+/?$"#,
        #"^/notes/[A-Za-z0-9_-]+/?$"#,
        #"^/p/[^/]+/[0-9]+/?$"#,
        #"^/post/[0-9]+/?$"#,
        #"^/(u|c)/[^/]+/?$"#,
    ]

    /// `instanceHost` is the host of the instance the user is logged in to (`larpnet.pl`).
    static func classify(_ url: URL, instanceHost: String?) -> LinkTarget {
        switch url.scheme?.lowercased() {
        case "web+mastodon": return classifyMastodonIntent(url)
        case "web+ap": return classifyWebAp(url, instanceHost: instanceHost)
        case "larpnet":
            guard let page = queryItem("url", in: url).flatMap(URL.init(string:)),
                  ["http", "https"].contains(page.scheme?.lowercased() ?? "") else {
                return .instancePage(nil)
            }
            return classify(page, instanceHost: instanceHost)
        case "http", "https": return classifyHttp(url, instanceHost: instanceHost)
        default: return .external(url)
        }
    }

    /// True when `query` is a `user@host` handle rather than a URL.
    static func isHandle(_ query: String) -> Bool {
        query.range(of: #"^@?[A-Za-z0-9_.-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }

    /// Mastodon's handler only defines `follow?uri=<handle or URL>` and `share?text=...`.
    private static func classifyMastodonIntent(_ url: URL) -> LinkTarget {
        switch url.host?.lowercased() {
        case "follow":
            guard var uri = queryItem("uri", in: url), !uri.isEmpty else { return .external(url) }
            if uri.hasPrefix("acct:") { uri.removeFirst(5) }
            if uri.hasPrefix("@") { uri.removeFirst() }
            return .resolve(uri)
        case "share":
            let text = [queryItem("text", in: url), queryItem("url", in: url)]
                .compactMap { $0 }.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return .share(text)
        default:
            return .external(url)
        }
    }

    /// FEP-07d7: `web+ap://host/path` is `https://host/path`.
    private static func classifyWebAp(_ url: URL, instanceHost: String?) -> LinkTarget {
        let rest = url.absoluteString.components(separatedBy: "://").dropFirst().joined(separator: "://")
        guard let https = URL(string: "https://" + rest) else { return .external(url) }
        switch classifyHttp(https, instanceHost: instanceHost) {
        // It names an ActivityPub object even when the path isn't a shape we know.
        case .external, .instancePage: return .resolve(https.absoluteString)
        case let target: return target
        }
    }

    private static func classifyHttp(_ url: URL, instanceHost: String?) -> LinkTarget {
        guard let host = url.host?.lowercased() else { return .external(url) }
        let path = url.path.isEmpty ? "/" : url.path
        let own = instanceHost.map { $0.lowercased() == host } ?? false

        // Hashtags: Mastodon-style /tags/x anywhere; Friendica's /search?tag=x on our instance.
        if let tag = firstGroup(#"^/tags/([^/]+)/?$"#, in: path) {
            return .hashtag(tag)
        }
        if own, path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "search",
           let tag = queryItem("tag", in: url), !tag.isEmpty {
            return .hashtag(tag.hasPrefix("#") ? String(tag.dropFirst()) : tag)
        }

        if own {
            if let nickname = firstGroup(#"^/(?:profile/|@)([^/]+)/?$"#, in: path) {
                return .localProfile(nickname: nickname)
            }
            if path.range(of: #"^/(display|item|objects)/[^/]+/?$"#, options: .regularExpression) != nil {
                return .resolve(url.absoluteString)
            }
            return .instancePage(url)
        }

        if fediversePaths.contains(where: { path.range(of: $0, options: .regularExpression) != nil }) {
            return .resolve(url.absoluteString)
        }
        return .external(url)
    }

    private static func queryItem(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

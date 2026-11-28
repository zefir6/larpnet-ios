import Foundation
import UIKit

/// Opens links: tapped in a post (`RootView`'s `openURL` action) or ones the app was opened
/// with (Universal Links, `larpnet://open`, `web+mastodon://`, `web+ap://`). Fediverse posts and
/// profiles are resolved through our server and shown natively in `pending`, which `RootView`
/// presents as a sheet; everything else goes to Safari. Rules: `LinkRouter`.
@MainActor
@Observable
final class LinkStore {
    /// What `RootView` shows in its link sheet.
    struct Destination: Identifiable {
        let id = UUID()
        let route: AppRoute
    }

    var pending: Destination?
    /// A `web+mastodon://share` link: `RootView` opens compose with this text.
    var pendingShareText: String?
    /// Set while a link is being resolved (the server may have to fetch it first).
    private(set) var isResolving = false
    /// Shown when a link couldn't be opened in the app.
    var failureMessage: String?

    private let tokenStore: TokenStore
    private let friendicaAPI: () throws -> FriendicaAPIClient

    init(tokenStore: TokenStore, friendicaAPI: @escaping () throws -> FriendicaAPIClient) {
        self.tokenStore = tokenStore
        self.friendicaAPI = friendicaAPI
    }

    /// `fromOutside`: the app was opened with this link. A page of ours without a screen in the
    /// app then just leaves the app open -- Safari would hand a Universal Link straight back.
    func open(_ url: URL, fromOutside: Bool) {
        guard tokenStore.isLoggedIn else { return }
        let host = tokenStore.instanceBaseURL.flatMap(URL.init(string:))?.host
        switch LinkRouter.classify(url, instanceHost: host) {
        case .hashtag(let tag):
            pending = Destination(route: .hashtag(tag))
        case .share(let text):
            pendingShareText = text
        case .localProfile(let nickname):
            Task {
                if let account = try? await friendicaAPI().lookupLocalAccount(nickname: nickname) {
                    pending = Destination(route: .profile(accountId: account.id))
                } else if !fromOutside {
                    openInSafari(url)
                }
            }
        case .resolve(let query):
            Task { await resolve(query, original: url, fromOutside: fromOutside) }
        case .instancePage(let page):
            if !fromOutside, let page { openInSafari(page) }
        case .external(let url):
            openInSafari(url)
        }
    }

    private func resolve(_ query: String, original: URL, fromOutside: Bool) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let api = try friendicaAPI()
            if LinkRouter.isHandle(query) {
                if let account = try await api.searchAccounts(query: query, limit: 1, resolve: true).first {
                    pending = Destination(route: .profile(accountId: account.id))
                    return
                }
            } else {
                let results = try await api.search(query: query)
                if let status = results.statuses.first {
                    pending = Destination(route: .thread(statusId: status.id))
                    return
                }
                if let account = results.accounts.first {
                    pending = Destination(route: .profile(accountId: account.id))
                    return
                }
            }
        } catch {
            // Falls through to the browser / message below.
        }
        if query.hasPrefix("http"), let url = URL(string: query), !(fromOutside && isOwnInstance(url)) {
            openInSafari(url)
        } else {
            failureMessage = String(localized: "Couldn't open this link in the app")
        }
    }

    private func isOwnInstance(_ url: URL) -> Bool {
        tokenStore.instanceBaseURL.flatMap(URL.init(string:))?.host?.lowercased() == url.host?.lowercased()
    }

    private func openInSafari(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

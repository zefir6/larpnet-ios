import Foundation

/// Hand-rolled dependency graph, no DI framework -- direct port of Android's
/// `di/AppContainer.kt`'s stated rationale (this app is small enough that a top-level object
/// graph built once and handed down covers it). Built once in `LarpnetApp.init()` and injected
/// via SwiftUI's `Environment`.
/// `@unchecked Sendable` -- every mutable piece of state here (`cachedClient`) is only ever
/// touched from `@MainActor`-isolated call sites (this class itself, and `BackgroundRefresh`'s
/// `@MainActor`-marked `poll`), so it's safe to capture across an isolation boundary into a
/// plain `Task { }` from non-isolated contexts like a `BGTaskScheduler` launch handler.
@MainActor
final class AppContainer: @unchecked Sendable {
    let tokenStore = TokenStore()
    lazy var recentTagsStore = RecentTagsStore(tokenStore: tokenStore)
    lazy var bottomNavOrderStore = BottomNavOrderStore(tokenStore: tokenStore)

    /// larpnet.pl sits behind Cloudflare, whose WAF blocks requests carrying a generic
    /// HTTP-library User-Agent with a 403 -- confirmed live (`curl` default UA -> 403,
    /// `larpnet-ios/<version>` -> 200 on the same `GET /api/v1/instance` call). Applied to
    /// *every* session below, including `imageSession` -- avatars are proxied through the
    /// server's own `/photo/contact/...` URLs, same block applies (this is the exact bug that
    /// bit Android's Coil setup, since `AsyncImage` has no session-injection point either --
    /// see `RemoteImage`).
    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "larpnet-ios/\(version)"
    }()

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    /// Used for both the unauthenticated `AuthAPI` calls and the authenticated
    /// `FriendicaAPIClient` calls -- unlike Android there's no separate OkHttp interceptor
    /// chain per client; the Bearer header is added per-request inside
    /// `FriendicaAPIClient.buildRequest` instead, so one shared session configuration (carrying
    /// just the User-Agent) covers both.
    let apiSession = makeSession()
    let imageSession = makeSession()
    lazy var imageLoader = ImageLoader(session: imageSession)

    func authAPI(baseURL: URL) -> AuthAPI {
        AuthAPI(baseURL: baseURL, session: apiSession)
    }

    lazy var oAuthFlow = OAuthFlow(tokenStore: tokenStore, authAPIFactory: { [apiSession] baseURL in
        AuthAPI(baseURL: baseURL, session: apiSession)
    })

    // Memoized by base URL, same as Android's `cachedApi` -- rebuilds only if the user logs
    // into a different instance.
    private var cachedClient: (String, FriendicaAPIClient)?

    func friendicaAPI() throws -> FriendicaAPIClient {
        guard let baseURLString = tokenStore.instanceBaseURL,
              let baseURL = URL(string: baseURLString) else {
            throw NetworkError.notLoggedIn
        }
        if let cached = cachedClient, cached.0 == baseURLString {
            return cached.1
        }
        let client = FriendicaAPIClient(baseURL: baseURL, session: apiSession, tokenStore: tokenStore)
        cachedClient = (baseURLString, client)
        return client
    }
}

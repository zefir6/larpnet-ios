import SwiftUI
import UIKit

/// Tiny dedicated image loader/cache, used instead of SwiftUI's `AsyncImage` everywhere in
/// this app. `AsyncImage` has no session-injection point, so it cannot carry the required
/// `User-Agent` header -- and larpnet.pl's Cloudflare WAF blocks the default one, exactly the
/// bug that bit Android's Coil setup for avatars/media (proxied through the server's own
/// `/photo/contact/...` URLs, same block applies). `AppContainer.imageSession` already carries
/// that header; this loader just needs to use it instead of `URLSession.shared`.
///
/// Not `@MainActor` -- `NSCache` is thread-safe, and keeping this off the main actor lets a
/// plain `static let` serve as `EnvironmentKey.defaultValue`.
final class ImageLoader: @unchecked Sendable {
    private let session: URLSession
    private let cache = NSCache<NSURL, UIImage>()

    init(session: URLSession) {
        self.session = session
    }

    func load(_ url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Drops one cached entry, forcing the next `load(_:)` for this exact URL to hit the network
    /// again. Kept alongside `store(_:for:)` below for cases where there's no already-known-good
    /// image to seed with -- just forcing a re-fetch is enough.
    func evict(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    /// Seeds the cache with an already-known-correct image for a URL -- used right after an
    /// avatar upload, where the just-uploaded bytes themselves are the freshest possible source
    /// of truth. This is stronger than `evict` + relying on a re-fetch: it sidesteps any
    /// question of whether an intermediate cache (Cloudflare, in this app's case) would still
    /// serve stale bytes for that URL even after eviction here -- `load(_:)` never has to touch
    /// the network at all to see the update, it's already sitting in this cache.
    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// Bump this to force a fresh `loader.load(url)` call even when `url` itself hasn't
    /// changed -- `.task(id:)` only restarts when its id actually differs, and since this view's
    /// own `@State private var image` is a local copy taken at fetch time, a cache mutation
    /// elsewhere (e.g. `ImageLoader.store`/`evict`) doesn't retroactively update an
    /// already-displayed image on its own. Defaults to 0 so every other call site in the app
    /// (which never needs this) is unaffected.
    var refreshToken: Int = 0
    @Environment(\.imageLoader) private var loader
    @State private var image: UIImage?

    private struct FetchID: Equatable {
        let url: URL?
        let refreshToken: Int
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .task(id: FetchID(url: url, refreshToken: refreshToken)) {
            image = nil
            guard let url else { return }
            image = await loader.load(url)
        }
    }
}

private struct ImageLoaderKey: EnvironmentKey {
    // Falls back to an unheadered session only if a view is previewed/used without the real
    // environment wired up -- every real call site gets `AppContainer.imageSession` via
    // `.environment(\.imageLoader, ...)` at the app root.
    static let defaultValue = ImageLoader(session: .shared)
}

extension EnvironmentValues {
    var imageLoader: ImageLoader {
        get { self[ImageLoaderKey.self] }
        set { self[ImageLoaderKey.self] = newValue }
    }
}

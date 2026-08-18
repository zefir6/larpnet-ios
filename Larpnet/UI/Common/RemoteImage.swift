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
}

struct RemoteImage: View {
    let url: URL?
    @Environment(\.imageLoader) private var loader
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .task(id: url) {
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

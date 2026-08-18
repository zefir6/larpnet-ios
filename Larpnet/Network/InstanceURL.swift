import Foundation

/// Normalizes a bare domain (e.g. "larpnet.pl") into a `https://larpnet.pl/`-shaped URL --
/// direct port of Android's `network/InstanceUrl.kt`. A trailing slash is required so relative
/// path resolution (`baseURL.appendingPathComponent(...)`) behaves the way Retrofit's `baseUrl`
/// contract expects.
enum InstanceURL {
    static func normalize(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        if !s.hasSuffix("/") {
            s += "/"
        }
        return URL(string: s)
    }
}

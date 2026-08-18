import Foundation

/// Direct port of Android's `data/model/Instance.kt`. `GET /api/v1/instance` emits many more
/// fields (confirmed live: `stats`, `configuration`, `contact_account`, etc.) -- only the
/// handful the app actually displays are declared here; the rest are silently ignored, same as
/// Kotlin's `ignoreUnknownKeys`.
struct Instance: Decodable, Sendable, Hashable {
    var uri: String
    var title: String
    var description: String
    var version: String

    enum CodingKeys: String, CodingKey {
        case uri, title, description, version
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = c.decode(.uri, default: "")
        title = c.decode(.title, default: "")
        description = c.decode(.description, default: "")
        version = c.decode(.version, default: "")
    }
}

import Foundation

/// One photo in a Friendica photo album -- shape mirrors `Photo/Lists.php` and
/// `Photoalbum/Show.php`'s response (not the fuller single-photo `GET api/friendica/photo`
/// shape, which has `link`/`scales` instead of a flat `thumb`), confirmed against Friendica's
/// `src/Factory/Api/Friendica/Photo.php`. `id` is the photo's `resource-id`, not its numeric
/// row id (that one's renamed `media-id` server-side and isn't needed here).
struct FriendicaPhoto: Decodable, Sendable, Hashable, Identifiable {
    var id: String
    var album: String
    var filename: String
    var type: String
    var thumb: String

    enum CodingKeys: String, CodingKey {
        case id, album, filename, type, thumb
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        album = c.decode(.album, default: "")
        filename = c.decode(.filename, default: "")
        type = c.decode(.type, default: "")
        thumb = c.decode(.thumb, default: "")
    }
}

/// One album summary from `GET api/friendica/photoalbums`, confirmed against
/// `Module/Api/Friendica/Photoalbum/Index.php`. No album id -- Friendica albums are identified
/// purely by name string, both here and in every other album endpoint.
struct FriendicaPhotoAlbum: Decodable, Sendable, Hashable, Identifiable {
    var name: String
    var count: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, count
    }

    init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.decode(.name, default: "")
        // PHP's DBA layer can hand back an aggregate COUNT(*) as either a JSON number or a
        // numeric string depending on the driver -- try both rather than risk silently
        // defaulting every album to a wrong "0 photos" count.
        if let intCount = try? c.decodeIfPresent(Int.self, forKey: .count) {
            count = intCount
        } else if let stringCount = try? c.decodeIfPresent(String.self, forKey: .count) {
            count = Int(stringCount) ?? 0
        } else {
            count = 0
        }
    }
}

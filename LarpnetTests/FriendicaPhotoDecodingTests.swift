import XCTest
@testable import Larpnet

/// Covers `FriendicaPhoto`/`FriendicaPhotoAlbum` decoding against fixtures shaped to match
/// Friendica's actual `api/friendica/photoalbums` and `api/friendica/photoalbum` responses --
/// field names verified against Friendica's own `develop`-branch source
/// (`src/Module/Api/Friendica/Photoalbum/Index.php`, `src/Factory/Api/Friendica/Photo.php`,
/// `Module/Api/Friendica/Photoalbum/Show.php`). The top-level shape (a **bare JSON array**, not
/// `{"albums": [...]}`/`{"photo": [...]}` the way the PHP source's `addFormattedContent` call
/// reads like it should produce) is now confirmed live: a real `photoalbums` call threw
/// `DecodingError.typeMismatch` ("expected Dictionary but found an array") against the
/// previous enveloped-object fixture, meaning Friendica's JSON response formatter strips that
/// wrapper key -- it's apparently only there to name the XML root element.
final class FriendicaPhotoDecodingTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture: \(name).json")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    func testDecodesPhotoAlbumsList() throws {
        let data = try loadFixture("photoalbums_list")
        let albums = try FriendicaJSON.decoder.decode(LossyArray<FriendicaPhotoAlbum>.self, from: data).elements
        XCTAssertEqual(albums.map(\.name), ["Larp 2026", "Costume ideas"])
        XCTAssertEqual(albums[0].count, 12, "a JSON number count must decode directly")
        XCTAssertEqual(albums[1].count, 3, "a JSON string count (PHP DBA aggregate quirk) must still coerce to Int")
    }

    func testDecodesPhotoalbumShowResponse() throws {
        let data = try loadFixture("photoalbum_show")
        let photos = try FriendicaJSON.decoder.decode(LossyArray<FriendicaPhoto>.self, from: data).elements
        let photo = try XCTUnwrap(photos.first)
        XCTAssertEqual(photo.id, "910d385c-d956afb9-a42059683490ec33", "id must be the resource-id, not media-id")
        XCTAssertEqual(photo.album, "Larp 2026")
        XCTAssertEqual(photo.filename, "group.jpg")
        XCTAssertEqual(photo.type, "image/jpeg")
        XCTAssertEqual(photo.thumb, "https://larpnet.pl/photo/910d385c-d956afb9-a42059683490ec33-3.jpg")
    }
}

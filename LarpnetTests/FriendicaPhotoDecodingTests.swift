import XCTest
@testable import Larpnet

/// Covers `FriendicaPhoto`/`FriendicaPhotoAlbum` decoding against fixtures shaped to match
/// Friendica's actual `api/friendica/photoalbums` and `api/friendica/photoalbum` responses --
/// field names verified against Friendica's own `develop`-branch source
/// (`src/Module/Api/Friendica/Photoalbum/Index.php`, `src/Factory/Api/Friendica/Photo.php`,
/// `Module/Api/Friendica/Photoalbum/Show.php`), not just the wiki docs, which mismatch the
/// source on a couple of endpoint paths. No live-captured fixture exists yet (unlike
/// `status_public_live.json`) since this needed an authenticated session against a real
/// Friendica instance this test suite doesn't have -- these fixtures should be swapped for a
/// verbatim capture the first time this is exercised against `larpnet.pl`.
final class FriendicaPhotoDecodingTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture: \(name).json")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    // Mirrors `FriendicaAPIClient`'s own private `PhotoAlbumsEnvelope`/`PhotoListEnvelope` --
    // duplicated here since those are file-private and not exposed even via `@testable import`.
    private struct AlbumsEnvelope: Decodable { let albums: [FriendicaPhotoAlbum] }
    private struct PhotoEnvelope: Decodable { let photo: LossyArray<FriendicaPhoto> }

    func testDecodesPhotoAlbumsList() throws {
        let data = try loadFixture("photoalbums_list")
        let envelope = try FriendicaJSON.decoder.decode(AlbumsEnvelope.self, from: data)
        XCTAssertEqual(envelope.albums.map(\.name), ["Larp 2026", "Costume ideas"])
        XCTAssertEqual(envelope.albums[0].count, 12, "a JSON number count must decode directly")
        XCTAssertEqual(envelope.albums[1].count, 3, "a JSON string count (PHP DBA aggregate quirk) must still coerce to Int")
    }

    func testDecodesPhotoalbumShowResponse() throws {
        let data = try loadFixture("photoalbum_show")
        let envelope = try FriendicaJSON.decoder.decode(PhotoEnvelope.self, from: data)
        let photo = try XCTUnwrap(envelope.photo.elements.first)
        XCTAssertEqual(photo.id, "910d385c-d956afb9-a42059683490ec33", "id must be the resource-id, not media-id")
        XCTAssertEqual(photo.album, "Larp 2026")
        XCTAssertEqual(photo.filename, "group.jpg")
        XCTAssertEqual(photo.type, "image/jpeg")
        XCTAssertEqual(photo.thumb, "https://larpnet.pl/photo/910d385c-d956afb9-a42059683490ec33-3.jpg")
    }
}

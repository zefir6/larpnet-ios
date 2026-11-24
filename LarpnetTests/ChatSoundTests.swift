import XCTest
import UserNotifications
@testable import Larpnet

/// `ChatSound`: the default, the bundled files, and that the choice lands in the App Group's
/// defaults (where `NotificationService` reads it).
final class ChatSoundTests: XCTestCase {
    private let key = "chat_sound"
    private var groupDefaults: UserDefaults! { UserDefaults(suiteName: MatrixSessionPaths.appGroupIdentifier) }
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = groupDefaults.string(forKey: key)
        groupDefaults.removeObject(forKey: key)
    }

    override func tearDown() {
        groupDefaults.set(saved, forKey: key)
        super.tearDown()
    }

    func testDefaultIsDoubleGlass() {
        XCTAssertEqual(ChatSound.current, .doubleGlass)
        XCTAssertNotNil(ChatSound.current.notificationSound)
    }

    func testSelectionIsStoredInAppGroup() {
        ChatSound.current = .bong
        XCTAssertEqual(groupDefaults.string(forKey: key), "bong")
        XCTAssertEqual(ChatSound.current, .bong)
    }

    func testUnknownStoredValueFallsBackToDefault() {
        groupDefaults.set("no_such_sound", forKey: key)
        XCTAssertEqual(ChatSound.current, .doubleGlass)
    }

    func testEveryLarpnetSoundIsBundled() {
        let app = Bundle(for: SettingsViewModel.self)
        for sound in ChatSound.allCases {
            switch sound {
            case .system:
                XCTAssertEqual(sound.notificationSound, .default)
            case .silent:
                XCTAssertNil(sound.notificationSound)
                XCTAssertNil(sound.fileName)
            default:
                let name = try? XCTUnwrap(sound.fileName)
                XCTAssertNotNil(
                    app.url(forResource: name.map { ($0 as NSString).deletingPathExtension }, withExtension: "caf"),
                    "\(sound) has no bundled file"
                )
            }
        }
    }

    /// Android uses the same keys (`push/ChatSounds.kt`).
    func testKeysMatchAndroid() {
        XCTAssertEqual(
            ChatSound.allCases.map(\.rawValue),
            ["double_glass", "glass", "short", "rising", "two_tone", "question", "bong",
             "pluck", "double_bong", "drop_glass", "system", "silent"]
        )
    }
}

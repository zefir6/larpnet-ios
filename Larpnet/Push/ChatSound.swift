import Foundation
import UserNotifications

/// The sound chat notifications play, picked in Settings -> Chat (`ChatSoundPickerView`). The
/// Larpnet sounds are `Resources/Sounds/*.caf` in the app bundle (Kenney's "Interface Sounds",
/// CC0, some joined into two-note sounds), so chat sounds different from everything else on
/// the phone by default. Mirrors Android's `push/ChatSounds.kt`, same sounds and keys.
///
/// Compiled into both the app and `NotificationServiceExtension` (see project.yml): the
/// extension sets the sound on every chat push, and the choice lives in the App Group's
/// defaults so it can read it.
enum ChatSound: String, CaseIterable, Identifiable, Sendable {
    case doubleGlass = "double_glass"
    case glass
    case short
    case rising
    case twoTone = "two_tone"
    case question
    case bong
    case pluck
    case doubleBong = "double_bong"
    case dropGlass = "drop_glass"
    /// The phone's own notification sound (what chat played before this setting existed).
    case system
    case silent

    static let `default`: ChatSound = .doubleGlass
    private static let defaultsKey = "chat_sound"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .doubleGlass: "Double glass (default)"
        case .glass: "Glass"
        case .short: "Short chime"
        case .rising: "Rising chime"
        case .twoTone: "Two tones"
        case .question: "Question"
        case .bong: "Bong"
        case .pluck: "Pluck"
        case .doubleBong: "Double bong"
        case .dropGlass: "Drop and glass"
        case .system: "Phone's default sound"
        case .silent: "Silent"
        }
    }

    /// The bundled file, for the Larpnet sounds.
    var fileName: String? {
        switch self {
        case .system, .silent: nil
        default: "chat_\(rawValue).caf"
        }
    }

    /// What to put on a chat notification's `content.sound`.
    var notificationSound: UNNotificationSound? {
        switch self {
        case .silent: nil
        case .system: .default
        default: fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) }
        }
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: MatrixSessionPaths.appGroupIdentifier)
    }

    static var current: ChatSound {
        get { defaults?.string(forKey: defaultsKey).flatMap(ChatSound.init(rawValue:)) ?? .default }
        set { defaults?.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

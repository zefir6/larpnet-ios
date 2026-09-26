import Foundation

/// Where the Matrix crypto/session store lives on disk -- the App Group container (not
/// `.applicationSupportDirectory`, which is private to whichever process created it), so both
/// the main app and `NotificationServiceExtension` can reach the same store. Both targets list
/// this exact file in their `sources` (see project.yml) rather than duplicating it, so there is
/// exactly one place this path is computed.
///
/// **Migration note**: before push notifications, this lived under the main app's own
/// `Application Support` directory. Moving it into the shared App Group container was required
/// for the extension to reach it at all -- an already-installed user's existing session simply
/// won't be found at the new path, so this is a one-time "new device" reset for anyone who
/// installed before this shipped (a fresh Matrix login, and -- if they'd set up cross-device
/// recovery -- a `restoreRecovery()` prompt to get old history back, same as installing the app
/// on a genuinely new phone). Deliberately accepted rather than writing a one-off migration
/// copier for a chat feature still in internal testing.
enum MatrixSessionPaths {
    static let appGroupIdentifier = "group.pl.larpnet.ios"

    static func sessionDirectory(for userId: String) throws -> URL {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw MatrixSessionPathsError.appGroupContainerUnavailable
        }
        let safe = userId.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: ":", with: "_")
        let dir = base.appendingPathComponent("MatrixSession", isDirectory: true).appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum MatrixSessionPathsError: Error {
    /// The App Groups entitlement/capability isn't set up correctly for this build -- either
    /// the `group.pl.larpnet.ios` App Group doesn't exist in the Apple Developer portal yet, or
    /// this target's App ID isn't associated with it.
    case appGroupContainerUnavailable
}

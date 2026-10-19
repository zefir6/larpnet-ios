import Foundation
import MatrixRustSDK

/// Every Matrix client this app builds -- the main app's and `NotificationServiceExtension`'s.
/// The version itself doesn't change how the app syncs (that's still plain `syncV2`), but
/// `NotificationClient.getNotification` refuses to run without one: it throws
/// `SlidingSync(VersionIsMissing)` instantly, so every chat push used to fall back to the
/// server's generic "New message" placeholder (found on larpnet-android, 2026-10-18). Both
/// test and prod Synapse support native sliding sync (`org.matrix.simplified_msc3575`).
enum MatrixClientConfig {
    static let slidingSync: SlidingSyncVersionBuilder = .native

    static func builder(homeserver: String, sessionDir: URL) -> ClientBuilder {
        ClientBuilder()
            .homeserverUrl(url: homeserver)
            .sessionPaths(dataPath: sessionDir.path, cachePath: sessionDir.path)
            .slidingSyncVersionBuilder(versionBuilder: slidingSync)
    }
}

/// Codable copy of the SDK's `Session`, stored in the shared Keychain
/// (`TokenStore.matrixSessionJSON`) by the main app after each chat login, so the notification
/// extension can `restoreSession` instead of logging in again on every push.
struct MatrixSavedSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let userId: String
    let deviceId: String
    let homeserverUrl: String

    init(_ session: Session) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userId = session.userId
        deviceId = session.deviceId
        homeserverUrl = session.homeserverUrl
    }

    var session: Session {
        Session(
            accessToken: accessToken, refreshToken: refreshToken, userId: userId,
            deviceId: deviceId, homeserverUrl: homeserverUrl, oauthData: nil,
            slidingSyncVersion: .native
        )
    }

    static func load(from tokenStore: TokenStore) -> MatrixSavedSession? {
        guard let json = tokenStore.matrixSessionJSON else { return nil }
        return try? JSONDecoder().decode(MatrixSavedSession.self, from: Data(json.utf8))
    }

    func save(to tokenStore: TokenStore) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        tokenStore.matrixSessionJSON = String(decoding: data, as: UTF8.self)
    }
}

import Foundation
import Security

/// Minimal generic-password Keychain wrapper -- no third-party dependency needed for this.
/// Every value is stored as a UTF-8 string under `service` (fixed) + `account` (the key name),
/// mirroring the handful of string fields Android keeps in `EncryptedSharedPreferences`.
struct KeychainStore: Sendable {
    private let service: String

    init(service: String = "pl.larpnet.ios.auth") {
        self.service = service
    }

    func get(_ key: String) -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeAll()
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for key: String) {
        guard let value else {
            remove(key)
            return
        }
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func remove(_ key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Direct port of Android's `data/auth/TokenStore.kt`. No refresh token field: confirmed
/// server-side (via the Android build-out) that larpnet.pl's OAuth tokens never expire and none
/// is ever issued -- the only lifecycle event is server-side revocation, surfaced as a 401/403
/// at request time (see `FriendicaAPIClient`'s force-logout broadcast).
final class TokenStore: @unchecked Sendable {
    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard

    /// The baked-in default server -- what a fresh install's login screen prefills, and what
    /// `preferredInstance` falls back to until the user changes it (in Settings, or simply by
    /// logging into a different instance).
    static let defaultInstance = "larpnet.pl"

    private enum Key {
        static let instanceBaseURL = "instance_base_url"
        static let clientId = "client_id"
        static let clientSecret = "client_secret"
        static let accessToken = "access_token"
        static let preferredInstance = "preferred_instance"
    }

    init() {
        // `Settings.bundle/Root.plist`'s own `DefaultValue` for this key isn't synced into
        // `UserDefaults` until the user actually opens the app's page in the iOS Settings app
        // -- registering it here too means the OS Settings field (and `preferredInstance`'s
        // own fallback below, belt-and-suspenders) both read "larpnet.pl" from first launch,
        // not just after someone happens to open Settings once.
        defaults.register(defaults: [Key.preferredInstance: Self.defaultInstance])
    }

    var instanceBaseURL: String? {
        get { keychain.get(Key.instanceBaseURL) }
        set { keychain.set(newValue, for: Key.instanceBaseURL) }
    }

    var clientId: String? {
        get { keychain.get(Key.clientId) }
        set { keychain.set(newValue, for: Key.clientId) }
    }

    var clientSecret: String? {
        get { keychain.get(Key.clientSecret) }
        set { keychain.set(newValue, for: Key.clientSecret) }
    }

    var accessToken: String? {
        get { keychain.get(Key.accessToken) }
        set { keychain.set(newValue, for: Key.accessToken) }
    }

    /// `pushEnabled` is not a secret -- kept in `UserDefaults`, and deliberately *not* cleared
    /// by `clear()`, matching Android's `TokenStore.pushEnabled` (survives logout).
    var pushEnabled: Bool {
        get { defaults.object(forKey: "push_enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "push_enabled") }
    }

    /// Whether the current session has agreed to `TermsGateView`'s terms. Cleared by `clear()`
    /// -- shown once per login, not once per device: logging out and back in (possibly as a
    /// different account) goes through the gate again, same as Apple's guideline 1.2 wants it
    /// presented before *each* registration/login, not just the device's first ever one.
    var hasAcceptedTerms: Bool {
        get { defaults.bool(forKey: "has_accepted_terms") }
        set { defaults.set(newValue, forKey: "has_accepted_terms") }
    }

    /// The bare domain (e.g. "larpnet.pl", not a full URL) the login screen prefills and
    /// Settings' "Server" control edits. Not a secret, so `UserDefaults`, not Keychain --
    /// and deliberately *not* cleared by `clear()`: it's what the *next* login uses, so wiping
    /// it on logout would defeat the point of remembering it. Falls back to `defaultInstance`
    /// until the user changes it in Settings or simply logs into a different instance (a
    /// successful login updates this to match, so it always reflects "what to try next").
    var preferredInstance: String {
        get { defaults.string(forKey: Key.preferredInstance) ?? Self.defaultInstance }
        set { defaults.set(newValue, forKey: Key.preferredInstance) }
    }

    var isLoggedIn: Bool {
        accessToken != nil && instanceBaseURL != nil
    }

    /// Comma-joined, most-recent-first, capped at 3 by `RecentTagsStore` before it ever writes
    /// here. Not a secret, so `UserDefaults`, and deliberately *not* cleared by `clear()` --
    /// same rationale as `preferredInstance`: it's a convenience for whoever logs in next, not
    /// session state.
    var recentTags: String? {
        get { defaults.string(forKey: "recent_tags") }
        set { defaults.set(newValue, forKey: "recent_tags") }
    }

    /// Comma-joined `BottomTab` raw values, in display order. Not a secret, so `UserDefaults`,
    /// and deliberately *not* cleared by `clear()` -- a UI preference, not session state.
    var bottomNavOrder: String? {
        get { defaults.string(forKey: "bottom_nav_order") }
        set { defaults.set(newValue, forKey: "bottom_nav_order") }
    }

    /// Generic comma-joined-string-list accessor, backing `LocalPostFilterStore`'s two
    /// instances (hidden/blocked post ids). Not secrets, so `UserDefaults`.
    func stringList(for key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setStringList(_ value: String?, for key: String) {
        defaults.set(value, forKey: key)
    }

    /// JSON-encoded `[FollowedThread]`. Not a secret, so `UserDefaults`, and deliberately *not*
    /// cleared by `clear()` -- same convenience-across-relogin treatment as `recentTags`.
    var followedThreadsJSON: String? {
        get { defaults.string(forKey: "followed_threads") }
        set { defaults.set(newValue, forKey: "followed_threads") }
    }

    /// The logged-in account's own id, used to tell "is this my post" apart from someone
    /// else's in `StatusCard`. Unlike every other property below `pushEnabled`, this one *is*
    /// session identity, not a UI preference -- it must be cleared on logout, or a different
    /// account logging in on the same device would silently inherit the previous user's id and
    /// mis-flag ownership of their posts.
    var currentAccountId: String? {
        get { defaults.string(forKey: "current_account_id") }
        set { defaults.set(newValue, forKey: "current_account_id") }
    }

    /// Clears the access token and cached app registration (client id/secret), but leaves
    /// `pushEnabled` alone -- same split as Android's `clear()`. Also clears `currentAccountId`
    /// -- session identity, not a UI preference like the properties above -- and
    /// `hasAcceptedTerms`, so `TermsGateView` is shown again before the next login.
    func clear() {
        instanceBaseURL = nil
        clientId = nil
        clientSecret = nil
        accessToken = nil
        currentAccountId = nil
        hasAcceptedTerms = false
    }
}

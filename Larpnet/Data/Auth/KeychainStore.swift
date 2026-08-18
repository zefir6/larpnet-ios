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

    private enum Key {
        static let instanceBaseURL = "instance_base_url"
        static let clientId = "client_id"
        static let clientSecret = "client_secret"
        static let accessToken = "access_token"
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

    var isLoggedIn: Bool {
        accessToken != nil && instanceBaseURL != nil
    }

    /// Clears the access token and cached app registration (client id/secret), but leaves
    /// `pushEnabled` alone -- same split as Android's `clear()`.
    func clear() {
        instanceBaseURL = nil
        clientId = nil
        clientSecret = nil
        accessToken = nil
    }
}

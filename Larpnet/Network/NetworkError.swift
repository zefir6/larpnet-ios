import Foundation

/// Mirrors the Android app's `network/NetworkError.kt` sealed class -- every repository/API
/// call surfaces one of these instead of a raw `Error`, so UI code never inspects status codes
/// directly. 401/403 map to `.auth` and are additionally broadcast on `AppContainer`'s
/// force-logout stream (see `FriendicaAPIClient`), same split of responsibility as Android's
/// `AuthInterceptor` + `safeApiCall`.
enum NetworkError: Error, Sendable {
    case network(underlying: String)
    case http(status: Int, body: String?)
    case auth
    case parse(underlying: String)
    case notLoggedIn
    case invalidURL
}

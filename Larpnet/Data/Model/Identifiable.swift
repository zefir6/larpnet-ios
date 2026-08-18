/// Analogue of Android's `data/model/Identifiable.kt` -- implemented by every model
/// `LinkHeaderPaging` needs an id from (as a fallback next-cursor when the `Link` response
/// header is absent). Named `HasID`, not `Identifiable`, to avoid colliding with SwiftUI's own
/// `Identifiable` protocol (which several of these types also conform to, for `List`/`ForEach`).
protocol HasID {
    var id: String { get }
}

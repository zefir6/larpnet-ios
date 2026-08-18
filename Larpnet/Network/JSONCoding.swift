import Foundation

/// Shared JSON decoding config for every Friendica API response.
///
/// Landmine (see plan doc): `JSONDecoder.DateDecodingStrategy.iso8601` rejects fractional
/// seconds, but larpnet.pl emits `created_at` as `"2026-08-18T12:30:24.000Z"` (confirmed live,
/// `GET /api/v1/timelines/public`) -- fractional seconds present. `ISO8601DateFormatter` with
/// `.withFractionalSeconds` handles that shape; a plain `.withInternetDateTime` formatter is
/// kept as a fallback in case some endpoint ever omits the fraction.
enum FriendicaJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in try decodeFriendicaDate(decoder) }
        return decoder
    }()

    // Never mutated after initialization, only used for read-only `date(from:)` calls, which
    // is safe to call concurrently -- `nonisolated(unsafe)` is warranted here rather than a
    // sign of a real data race.
    nonisolated(unsafe) private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let withoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func decodeFriendicaDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = withFractional.date(from: raw) ?? withoutFractional.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unrecognized date format: \(raw)"
        )
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent(...) ?? default`, in one call -- used throughout the model layer so
    /// every optional-with-a-default field reads as one line, matching the Kotlin
    /// `@Serializable` default-value declarations it mirrors. Absorbs both a missing key *and*
    /// an explicit JSON `null`, which Swift's synthesized `Decodable` does not tolerate on a
    /// non-optional property (unlike Kotlin's `coerceInputValues`).
    func decode<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}

/// Wraps a `[Decodable]` decode so one malformed element doesn't blank an entire page --
/// Kotlin's `ignoreUnknownKeys`/`coerceInputValues` already gets this resilience for free at
/// the single-object level; Swift needs it made explicit at the array level.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(EmptyDecodable.self)
            }
        }
        elements = result
    }
}

private struct EmptyDecodable: Decodable {}

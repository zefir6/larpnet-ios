import Foundation

/// `api/v2/search`. Hashtags are left out: only link resolution uses this.
struct SearchResults: Decodable, Sendable {
    let accounts: [Account]
    let statuses: [Status]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        statuses = try container.decodeIfPresent([Status].self, forKey: .statuses) ?? []
    }

    private enum CodingKeys: String, CodingKey { case accounts, statuses }
}

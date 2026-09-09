import Foundation

/// Shared "respond to a pending incoming follow request" sequencing, used by both the Contacts
/// screen's Requests segment and Notifications' inline follow-request row -- keeps the
/// authorize-then-optionally-follow-back order in one place instead of duplicating it.
enum FollowRequestActions {
    static func accept(_ account: Account, api: FriendicaAPIClient) async throws {
        _ = try await api.respondToFollowRequest(accountId: account.id, action: "authorize")
    }

    static func acceptAndFollowBack(_ account: Account, api: FriendicaAPIClient) async throws {
        _ = try await api.respondToFollowRequest(accountId: account.id, action: "authorize")
        _ = try await api.follow(id: account.id)
    }

    static func decline(_ account: Account, api: FriendicaAPIClient) async throws {
        _ = try await api.respondToFollowRequest(accountId: account.id, action: "reject")
    }
}

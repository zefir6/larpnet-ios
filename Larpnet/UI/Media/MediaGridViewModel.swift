import Foundation

/// One media attachment paired with the id of the post it came from, so tapping it can open
/// that post's thread.
struct MediaGridItem: Identifiable {
    let statusId: String
    let media: MediaAttachment

    var id: String { media.id }
}

/// A grid of every photo attached to the user's own posts. No dedicated Friendica/Mastodon API
/// exists for this (Friendica's own `Module\Profile\Media` is an HTML web-profile page, not a
/// JSON API route) -- built client-side instead by paginating the user's own statuses (same
/// `getAccountStatuses` call `ProfileViewModel` already uses) and flattening each page's
/// `Status.mediaAttachments`.
@MainActor
@Observable
final class MediaGridViewModel {
    private(set) var items: [MediaGridItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var accountId: String?
    private var nextMaxId: String?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    func loadInitial() async {
        guard items.isEmpty, accountId == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let api = try appContainer.friendicaAPI()
            let me = try await api.verifyCredentials()
            accountId = me.id
            let page = try await api.getAccountStatuses(id: me.id)
            items = Self.flatten(page.items)
            nextMaxId = page.nextMaxId
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadMore() async {
        guard !isLoadingMore, let accountId, let maxId = nextMaxId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await appContainer.friendicaAPI().getAccountStatuses(id: accountId, maxId: maxId)
            items.append(contentsOf: Self.flatten(page.items))
            nextMaxId = page.nextMaxId
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private static func flatten(_ statuses: [Status]) -> [MediaGridItem] {
        statuses.flatMap { status in
            (status.reblog ?? status).mediaAttachments.map { MediaGridItem(statusId: status.id, media: $0) }
        }
    }
}

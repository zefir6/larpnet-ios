import Foundation

/// Direct port of Android's `ui/search/SearchViewModel.kt`: 300ms debounced account search,
/// single page only (no Link header on this endpoint).
@MainActor
@Observable
final class SearchViewModel {
    var query: String = "" {
        didSet { scheduleSearch() }
    }
    private(set) var results: [Account] = []
    private(set) var isSearching = false
    var errorMessage: String?

    private let appContainer: AppContainer
    private var searchTask: Task<Void, Never>?

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.search(trimmed)
        }
    }

    private func search(_ query: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let api = try appContainer.friendicaAPI()
            results = try await api.searchAccounts(query: query)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

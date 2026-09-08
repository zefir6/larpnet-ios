import SwiftUI

struct LocalPostListView: View {
    @State private var viewModel: LocalPostListViewModel
    let title: String
    let removeActionLabel: String
    let onOpenThread: (Status) -> Void
    let onOpenProfile: (String) -> Void

    init(
        title: String, removeActionLabel: String, store: LocalPostFilterStore, appContainer: AppContainer,
        onOpenThread: @escaping (Status) -> Void,
        onOpenProfile: @escaping (String) -> Void
    ) {
        self.title = title
        self.removeActionLabel = removeActionLabel
        _viewModel = State(initialValue: LocalPostListViewModel(store: store, appContainer: appContainer))
        self.onOpenThread = onOpenThread
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        if let status = entry.status {
                            // No `.postModerationHost` attached on this screen -- `StatusCard`'s
                            // moderation context menu naturally stays absent since there's
                            // nothing to hide/block/report from within a list of already
                            // hidden/blocked posts.
                            StatusCard(status: status, onOpenThread: onOpenThread, onOpenProfile: onOpenProfile)
                        } else {
                            Text("Post unavailable")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .larpnetCard()
                        }
                        Button(removeActionLabel) { viewModel.remove(entry.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.leading, 4)
                    }
                    .padding(.horizontal, 6)
                }
                if viewModel.entries.isEmpty, !viewModel.isLoading {
                    Text("Nothing here.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
            .padding(.top, 8)
        }
        .background(LarpnetTheme.pageBackground)
        .overlay {
            if viewModel.isLoading, viewModel.entries.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

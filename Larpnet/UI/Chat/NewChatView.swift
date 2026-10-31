import SwiftUI

/// "New chat" / "Add person" recipient picker. Replaces reusing `SearchView` for this: an empty
/// search screen gave no hint who to message, and on iOS 26+ its `.searchable` field stayed
/// hidden until pulled down, so the screen looked blank apart from the Matrix-address box.
///
/// Before typing: Recent (1:1 partners, newest first), then Everyone (local directory, A-Z).
/// While typing: one flat list of matches. Only local accounts are offered -- Matrix
/// identities exist only for them (see `larpnet_matrix_localpart()`); a federated address can
/// still be typed into the Matrix-address section at the bottom.
struct NewChatView: View {
    @State private var viewModel: NewChatViewModel
    @State private var customAddress = ""
    let title: String
    let onSelectAccount: (Account) -> Void
    var onEnterMatrixAddress: ((String) -> Void)?

    init(
        appContainer: AppContainer,
        title: String = "New chat",
        onSelectAccount: @escaping (Account) -> Void,
        onEnterMatrixAddress: ((String) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: NewChatViewModel(appContainer: appContainer))
        self.title = title
        self.onSelectAccount = onSelectAccount
        self.onEnterMatrixAddress = onEnterMatrixAddress
    }

    var body: some View {
        List {
            if viewModel.queryIsBlank {
                if !viewModel.recent.isEmpty {
                    Section("Recent") {
                        ForEach(viewModel.recent) { accountRow($0) }
                    }
                }
                if !viewModel.everyone.isEmpty {
                    Section(viewModel.recent.isEmpty ? "People on Larpnet" : "Everyone") {
                        ForEach(viewModel.everyone) { accountRow($0) }
                    }
                }
            } else {
                ForEach(viewModel.matches) { accountRow($0) }
            }
            if let onEnterMatrixAddress {
                Section {
                    TextField("@user:server", text: $customAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Start chat") {
                        let trimmed = customAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onEnterMatrixAddress(trimmed)
                    }
                    .disabled(customAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Matrix address")
                } footer: {
                    Text("For someone on another Matrix server.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LarpnetTheme.pageBackground)
        // `.always`: with an inline title the default placement hides the field until the
        // list is pulled down, which made this screen look empty.
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Name or @nickname"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .overlay {
            if viewModel.queryIsBlank, viewModel.isLoading, viewModel.recent.isEmpty, viewModel.everyone.isEmpty {
                ProgressView()
            } else if !viewModel.queryIsBlank, viewModel.matches.isEmpty {
                if viewModel.isSearching {
                    ProgressView()
                } else {
                    Text("No one found").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadIfNeeded() }
    }

    private func accountRow(_ account: Account) -> some View {
        Button { onSelectAccount(account) } label: {
            AccountRow(account: account)
        }
        .buttonStyle(.plain)
    }
}

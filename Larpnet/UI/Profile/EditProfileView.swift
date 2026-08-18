import SwiftUI

struct EditProfileView: View {
    @State private var viewModel: EditProfileViewModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    init(appContainer: AppContainer, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: EditProfileViewModel(appContainer: appContainer))
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section("Display name") {
                TextField("Display name", text: $viewModel.displayName)
            }
            Section("Bio") {
                TextEditor(text: $viewModel.note).frame(minHeight: 100)
            }
            Section("Privacy") {
                Toggle("Manually approve followers", isOn: $viewModel.locked)
                Toggle("Discoverable", isOn: $viewModel.discoverable)
                Toggle("Bot account", isOn: $viewModel.bot)
            }
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if await viewModel.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .overlay {
            if viewModel.isLoading { ProgressView() }
        }
        .task { await viewModel.load() }
    }
}

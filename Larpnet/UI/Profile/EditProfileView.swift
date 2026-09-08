import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @State private var viewModel: EditProfileViewModel
    @State private var avatarPickerItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    init(appContainer: AppContainer, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: EditProfileViewModel(appContainer: appContainer))
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer(minLength: 0)
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        ZStack {
                            RemoteImage(url: URL(string: viewModel.avatarURL))
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                            if viewModel.isUploadingAvatar {
                                Circle().fill(.black.opacity(0.4)).frame(width: 88, height: 88)
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.caption)
                                    .padding(6)
                                    .background(.black.opacity(0.6), in: Circle())
                                    .foregroundStyle(.white)
                                    .offset(x: 32, y: 32)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isUploadingAvatar)
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
            }
            .onChange(of: avatarPickerItem) { _, newValue in
                guard let newValue else { return }
                viewModel.uploadAvatar(newValue)
                avatarPickerItem = nil
            }

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

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
        // Read once here (`body` is `@MainActor`) rather than inline inside `PhotosPicker`'s
        // `label` closure below -- that closure comes from a PhotosUI/SwiftUI cross-import
        // overlay that isn't annotated `@MainActor` for Swift 6 strict concurrency, so touching
        // `viewModel` (itself `@MainActor`) directly inside it trips "can not be referenced from
        // a nonisolated context". These are plain value types, so hoisting them changes nothing
        // behaviorally -- `body` already re-runs on every relevant state change regardless.
        let avatarURL = viewModel.avatarURL
        let avatarVersion = viewModel.avatarVersion
        let isUploadingAvatar = viewModel.isUploadingAvatar

        Form {
            Section {
                HStack {
                    Spacer(minLength: 0)
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        ZStack {
                            RemoteImage(url: URL(string: avatarURL), refreshToken: avatarVersion)
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                            if isUploadingAvatar {
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
                viewModel.stageAvatarForCropping(newValue)
                avatarPickerItem = nil
            }

            // Right under the avatar, not at the bottom of the form -- an avatar-upload error
            // needs to be visible without scrolling past Display name/Bio/Privacy first (a real
            // upload failure was confirmed live to go unnoticed here before this moved up).
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
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
                .disabled(viewModel.isSaving || viewModel.isUploadingAvatar)
            }
        }
        .overlay {
            if viewModel.isLoading { ProgressView() }
        }
        .task { await viewModel.load() }
        .sheet(
            isPresented: Binding(
                get: { viewModel.imageToCrop != nil },
                set: { if !$0 { viewModel.cancelCropping() } }
            )
        ) {
            if let imageToCrop = viewModel.imageToCrop {
                AvatarCropView(
                    image: imageToCrop,
                    onCancel: { viewModel.cancelCropping() },
                    onCrop: { viewModel.uploadAvatar($0) }
                )
            }
        }
    }
}

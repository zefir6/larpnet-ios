import PhotosUI
import SwiftUI

/// Direct port of Android's `ui/compose/ComposeScreen.kt`, presented as a `.sheet` (see
/// `AppRoute.swift`) rather than a pushed route.
struct ComposeView: View {
    @State private var viewModel: ComposeViewModel
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingAudiencePicker = false
    @Environment(\.dismiss) private var dismiss
    let onPosted: () -> Void

    init(context: ComposeContext, appContainer: AppContainer, onPosted: @escaping () -> Void) {
        _viewModel = State(initialValue: ComposeViewModel(replyToId: context.replyToId, appContainer: appContainer))
        self.onPosted = onPosted
    }

    private static let visibilities = ["public", "unlisted", "private", "local"]
    private static let visibilityLabels = [
        "public": "Public", "unlisted": "Unlisted", "private": "Followers only",
        "local": "Larpnet only",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $viewModel.text)
                        .frame(minHeight: 120)
                }

                Section {
                    Toggle("Content warning", isOn: $viewModel.isSpoilerEnabled)
                    if viewModel.isSpoilerEnabled {
                        TextField("Warning text", text: $viewModel.spoilerText)
                    }
                    if !viewModel.isCustomAudience {
                        Toggle("Sensitive media", isOn: $viewModel.sensitive)
                    }
                }

                if !viewModel.isCustomAudience {
                    Section("Visibility") {
                        // `.menu`, not `.segmented` -- four options (adding "Server only"
                        // alongside the original three) stopped fitting comfortably as segments
                        // on a phone-width screen, and a dropdown is what Android/the web ACL
                        // selector both use for this picker anyway.
                        Picker("Visibility", selection: $viewModel.visibility) {
                            ForEach(Self.visibilities, id: \.self) { visibility in
                                Label(Self.visibilityLabels[visibility] ?? visibility, systemImage: VisibilityIcon.systemName(for: visibility))
                                    .tag(visibility)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Toggle("Choose specific people/groups", isOn: $viewModel.isCustomAudience)
                    if viewModel.isCustomAudience {
                        Button {
                            showingAudiencePicker = true
                        } label: {
                            HStack {
                                Text("Audience")
                                Spacer()
                                Text(audienceSummary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !viewModel.isCustomAudience {
                    Section("Media") {
                        PhotosPicker("Add photo", selection: $photoPickerItem, matching: .images)
                        if !viewModel.pendingMedia.isEmpty {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(viewModel.pendingMedia) { media in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: media.image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 80, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay {
                                                    if media.isUploading { ProgressView() }
                                                }
                                            Button {
                                                viewModel.removeMedia(media.id)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Photos aren't supported on custom-audience posts yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.replyToId == nil ? "New Post" : "Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        Task {
                            if await viewModel.publish() {
                                onPosted()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canPublish)
                }
            }
            .onChange(of: photoPickerItem) { _, newValue in
                if let newValue { viewModel.addMedia(newValue) }
                photoPickerItem = nil
            }
            .onChange(of: viewModel.isCustomAudience) { _, isCustomAudience in
                if isCustomAudience { Task { await viewModel.loadAudienceIfNeeded() } }
            }
            .sheet(isPresented: $showingAudiencePicker) {
                AudiencePickerView(viewModel: viewModel)
            }
        }
    }

    private var audienceSummary: String {
        let count = viewModel.selectedCircleIds.count + viewModel.selectedAccountIds.count
        return count == 0 ? "None selected" : "\(count) selected"
    }
}

import SwiftUI

/// Multi-select audience picker for a custom-audience post -- circles and individual followers,
/// mixed freely (see `FriendicaAPIClient.postStatusWithACL`). Presented as a sheet from
/// `ComposeView`; selections live on `ComposeViewModel` directly so they survive the sheet being
/// dismissed and reopened.
struct AudiencePickerView: View {
    let viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.circles.isEmpty, viewModel.followers.isEmpty, viewModel.isLoadingAudience {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    if !viewModel.circles.isEmpty {
                        Section("Groups") {
                            ForEach(viewModel.circles) { circle in
                                Button {
                                    viewModel.toggleCircle(circle.id)
                                } label: {
                                    HStack {
                                        Text(circle.title)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if viewModel.selectedCircleIds.contains(circle.id) {
                                            Image(systemName: "checkmark").foregroundStyle(LarpnetTheme.accent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !viewModel.followers.isEmpty {
                        Section("People") {
                            ForEach(viewModel.followers) { account in
                                Button {
                                    viewModel.toggleAccount(account.id)
                                } label: {
                                    HStack {
                                        AccountRow(account: account)
                                        if viewModel.selectedAccountIds.contains(account.id) {
                                            Image(systemName: "checkmark").foregroundStyle(LarpnetTheme.accent)
                                        }
                                    }
                                }
                                .onAppear {
                                    if account.id == viewModel.followers.last?.id {
                                        Task { await viewModel.loadMoreFollowers() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

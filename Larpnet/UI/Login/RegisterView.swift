import SwiftUI

/// In-app account registration, presented as a sheet from `LoginView`. See `RegisterViewModel`.
struct RegisterView: View {
    @State private var viewModel: RegisterViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onLoggedIn: () -> Void
    /// Close the sheet and start the normal browser login.
    let onLogIn: () -> Void

    init(appContainer: AppContainer, onLoggedIn: @escaping () -> Void, onLogIn: @escaping () -> Void) {
        _viewModel = State(initialValue: RegisterViewModel(appContainer: appContainer))
        self.onLoggedIn = onLoggedIn
        self.onLogIn = onLogIn
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = viewModel.message {
                    Section {
                        Text(message.text)
                            .foregroundStyle(message.isInfo ? LarpnetTheme.accent : .red)
                        if message.useWebsite {
                            Button("Create an account on the website") { openWebsite("register") }
                        }
                    }
                }

                switch viewModel.step {
                case .form:
                    formSections
                case .code(_, let email, let approvalRequired):
                    codeSections(email: email, approvalRequired: approvalRequired)
                case .approvalPending:
                    finished("Email address confirmed. Your account now waits for approval by an admin -- you'll get an email when it's approved. Then log in.")
                case .logIn:
                    finished("Email address confirmed, your account is active. Log in.")
                case .loggedIn:
                    ProgressView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(LarpnetTheme.pageBackground)
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(viewModel.busy)
            .onChange(of: viewModel.step) { _, step in
                if step == .loggedIn { onLoggedIn() }
            }
        }
    }

    @ViewBuilder
    private var formSections: some View {
        Section {
            TextField("Full name", text: $viewModel.displayName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
        } footer: {
            Text("This is how others see you. Enter your first and last name.")
        }
        Section {
            TextField("Username", text: Binding(
                get: { viewModel.username },
                set: { viewModel.username = $0.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") } }
            ))
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
            Text("Lowercase letters, digits and _. Your address: name@\(viewModel.instanceHost)")
        }
        Section {
            TextField("Email address", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        Section {
            SecureField("Password", text: $viewModel.password)
                .textContentType(.newPassword)
            SecureField("Repeat password", text: $viewModel.passwordRepeat)
                .textContentType(.newPassword)
        } footer: {
            Text(viewModel.passwordsMatch ? "At least 8 characters" : "Passwords don't match")
                .foregroundStyle(viewModel.passwordsMatch ? Color.secondary : Color.red)
        }
        Section {
            TextField("A few words about you (optional)", text: $viewModel.reason, axis: .vertical)
                .lineLimit(2...5)
        } footer: {
            Text("If the account needs approval, an admin reads this.")
        }
        Section {
            Button {
                viewModel.submit()
            } label: {
                HStack {
                    Spacer()
                    if viewModel.busy { ProgressView() } else { Text("Create account").bold() }
                    Spacer()
                }
            }
            .disabled(!viewModel.canSubmit)
            Button("Create an account on the website") { openWebsite("register") }
        }
    }

    @ViewBuilder
    private func codeSections(email: String, approvalRequired: Bool) -> some View {
        Section {
            Text("We sent a code to \(email). Enter it below to confirm your address.")
            if approvalRequired {
                Text("After you confirm your address, an admin still has to approve the account.")
                    .font(.footnote)
            }
            TextField("Code from the email", text: Binding(
                get: { viewModel.code },
                set: { viewModel.code = String($0.filter(\.isNumber).prefix(6)) }
            ))
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
        }
        Section {
            Button {
                viewModel.confirm()
            } label: {
                HStack {
                    Spacer()
                    if viewModel.busy { ProgressView() } else { Text("Confirm").bold() }
                    Spacer()
                }
            }
            .disabled(!viewModel.canConfirm)
            Button("Send the email again") { viewModel.resend() }
            Button("I clicked the link in the email") { viewModel.linkUsed() }
        } footer: {
            Text("No email? Check your spam folder. Unconfirmed accounts are deleted after 48 hours.")
        }
    }

    @ViewBuilder
    private func finished(_ text: String) -> some View {
        Section {
            Text(text)
            Button("Log in") {
                dismiss()
                onLogIn()
            }
            .bold()
        }
    }

    private func openWebsite(_ path: String) {
        if let url = viewModel.baseURL?.appendingPathComponent(path) {
            openURL(url)
        }
    }
}

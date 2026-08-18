import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    let onLoggedIn: () -> Void

    init(appContainer: AppContainer, onLoggedIn: @escaping () -> Void) {
        _viewModel = State(initialValue: LoginViewModel(
            oAuthFlow: appContainer.oAuthFlow, tokenStore: appContainer.tokenStore
        ))
        self.onLoggedIn = onLoggedIn
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Larpnet")
                .font(.custom(LarpnetTheme.FontName.bold, size: 34))
                .foregroundStyle(LarpnetTheme.navBar)
            TextField("Instance (e.g. larpnet.pl)", text: $viewModel.instanceInput)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal)

            switch viewModel.uiState {
            case .idle:
                Button("Log in") { viewModel.login() }
                    .buttonStyle(.borderedProminent)
                    .tint(LarpnetTheme.navBar)
            case .awaitingBrowser, .exchangingToken:
                ProgressView("Opening browser…")
            case .error(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Try again") { viewModel.login() }
                    .buttonStyle(.borderedProminent)
                    .tint(LarpnetTheme.navBar)
            case .loggedIn:
                ProgressView()
            }
            Spacer()
        }
        .onChange(of: viewModel.uiState) { _, newValue in
            if newValue == .loggedIn { onLoggedIn() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LarpnetTheme.pageBackground)
    }
}

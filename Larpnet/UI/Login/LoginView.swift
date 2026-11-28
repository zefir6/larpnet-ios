import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @State private var showsRegistration = false
    private let appContainer: AppContainer
    let onLoggedIn: () -> Void

    init(appContainer: AppContainer, onLoggedIn: @escaping () -> Void) {
        _viewModel = State(initialValue: LoginViewModel(
            oAuthFlow: appContainer.oAuthFlow, tokenStore: appContainer.tokenStore
        ))
        self.appContainer = appContainer
        self.onLoggedIn = onLoggedIn
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Larpnet")
                .font(.custom(LarpnetTheme.FontName.bold, size: 34))
                .foregroundStyle(LarpnetTheme.navBar)

            switch viewModel.uiState {
            case .idle:
                Button("Log in") { viewModel.login() }
                    .buttonStyle(.borderedProminent)
                    .tint(LarpnetTheme.navBar)
                Text("Don't have an account yet?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                Button("Create account") { showsRegistration = true }
                    .buttonStyle(.bordered)
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
        .sheet(isPresented: $showsRegistration) {
            RegisterView(
                appContainer: appContainer,
                onLoggedIn: {
                    showsRegistration = false
                    onLoggedIn()
                },
                onLogIn: { viewModel.login() }
            )
        }
        .onChange(of: viewModel.uiState) { _, newValue in
            if newValue == .loggedIn { onLoggedIn() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LarpnetTheme.pageBackground)
    }
}

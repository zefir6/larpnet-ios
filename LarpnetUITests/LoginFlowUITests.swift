import XCTest

/// Drives the real OAuth2 + Friendica login flow end to end against live `larpnet.pl` and
/// captures a screenshot of each main screen once logged in -- used to visually verify theming
/// changes without a human re-entering credentials by hand each time.
///
/// Credentials are never hardcoded here: pass them as environment variables when invoking
/// `xcodebuild test`, e.g.
///   `xcodebuild test ... TEST_RUNNER_LARPNET_TEST_USERNAME=... TEST_RUNNER_LARPNET_TEST_PASSWORD=...`
/// (Xcode strips the `TEST_RUNNER_` prefix and exposes the rest to the test process's
/// environment.) If unset, every test in this file skips rather than failing the run.
final class LoginFlowUITests: XCTestCase {
    private var username: String!
    private var password: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let username = env["LARPNET_TEST_USERNAME"], let password = env["LARPNET_TEST_PASSWORD"] else {
            throw XCTSkip("Set LARPNET_TEST_USERNAME / LARPNET_TEST_PASSWORD (via TEST_RUNNER_* env vars) to run this test.")
        }
        self.username = username
        self.password = password
    }

    func testLoginAndCaptureMainScreens() throws {
        let app = XCUIApplication()
        app.launch()

        let loginButton = app.buttons["Log in"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 10), "Login screen did not appear")
        loginButton.tap()

        // ASWebAuthenticationSession's "wants to use X to sign in" system consent alert --
        // shown intermittently depending on OS/account state, so this is opportunistic, not
        // asserted.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemContinue = springboard.buttons["Continue"]
        if systemContinue.waitForExistence(timeout: 5) {
            systemContinue.tap()
        }

        // The login form is server-rendered HTML inside the authentication sheet's web view --
        // field order (username, then password) is stable regardless of exact accessibility
        // labeling, so index into webViews rather than relying on a label match.
        let usernameField = app.webViews.textFields.element(boundBy: 0)
        XCTAssertTrue(usernameField.waitForExistence(timeout: 15), "Login form did not appear in the auth sheet")
        usernameField.tap()
        usernameField.typeText(username)

        let passwordField = app.webViews.secureTextFields.element(boundBy: 0)
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(password)

        let signInButton = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        signInButton.tap()

        // First-time authorization consent page ("Do you want to authorize this application
        // ...?" / Yes / No) -- only appears if this app+account combination hasn't already
        // acknowledged it, so this step is opportunistic too.
        let authorizeYes = app.webViews.buttons["Yes"]
        if authorizeYes.waitForExistence(timeout: 8) {
            authorizeYes.tap()
        }

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 20), "Did not reach the logged-in timeline")
        sleep(2)
        attachScreenshot(named: "Home Timeline", of: app)

        for (label, name) in [("Larpnet", "Larpnet Timeline"), ("Directory", "Directory"), ("Notifications", "Notifications"), ("Settings", "Settings")] {
            let tab = app.tabBars.buttons[label]
            if tab.waitForExistence(timeout: 5) {
                tab.tap()
                sleep(2)
                attachScreenshot(named: name, of: app)
            }
        }
    }

    private func attachScreenshot(named name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

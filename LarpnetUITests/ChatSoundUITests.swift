import XCTest

/// Settings -> Chat -> Message sound, end to end: picks a sound and checks the Settings row
/// shows it. Logs in first if needed (same env-var credentials as `LoginFlowUITests`), against
/// `LARPNET_TEST_INSTANCE` when set (e.g. test.larpnet.pl).
final class ChatSoundUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPickChatSound() throws {
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        if let instance = env["LARPNET_TEST_INSTANCE"], !instance.isEmpty {
            app.launchArguments += ["-preferred_instance", instance]
        }
        app.launch()

        let agree = app.buttons["Agree and Continue"]
        if agree.waitForExistence(timeout: 5) {
            agree.tap()
        }
        try logInIfNeeded(app, env: env)
        allowNotificationsIfAsked(app)

        try openSettings(app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Message sound'")).firstMatch
        XCTAssertTrue(scrollTo(row, in: app), "No 'Message sound' row in Settings")
        attach("Settings row before", app)
        row.tap()

        XCTAssertTrue(app.navigationBars["Message sound"].waitForExistence(timeout: 5))
        attach("Picker", app)
        app.buttons["Bong"].tap()
        XCTAssertTrue(app.buttons["Bong"].isSelected, "Bong not marked selected")
        attach("Picker, Bong picked", app)

        app.navigationBars.buttons.firstMatch.tap()
        let updated = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Message sound' AND label CONTAINS 'Bong'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5), "Settings row doesn't show the new sound")
        attach("Settings row after", app)

        // Leave the default for whoever uses this simulator next.
        updated.tap()
        app.buttons["Double glass (default)"].tap()
        app.navigationBars.buttons.firstMatch.tap()
    }

    private func logInIfNeeded(_ app: XCUIApplication, env: [String: String]) throws {
        let loginButton = app.buttons["Log in"]
        guard loginButton.waitForExistence(timeout: 8) else { return }
        guard let username = env["LARPNET_TEST_USERNAME"], let password = env["LARPNET_TEST_PASSWORD"] else {
            throw XCTSkip("Not logged in; set LARPNET_TEST_USERNAME / LARPNET_TEST_PASSWORD (via TEST_RUNNER_*).")
        }
        loginButton.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Continue"].waitForExistence(timeout: 5) {
            springboard.buttons["Continue"].tap()
        }
        let usernameField = app.webViews.textFields.element(boundBy: 0)
        XCTAssertTrue(usernameField.waitForExistence(timeout: 15), "Login form did not appear")
        usernameField.tap()
        usernameField.typeText(username)
        let passwordField = app.webViews.secureTextFields.element(boundBy: 0)
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(password)
        app.webViews.buttons["Sign in"].tap()
        if app.webViews.buttons["Yes"].waitForExistence(timeout: 8) {
            app.webViews.buttons["Yes"].tap()
        }
        // The system's "Save Password?" sheet after signing in.
        let notNow = app.buttons["Not Now"].firstMatch
        if notNow.waitForExistence(timeout: 6) {
            notNow.tap()
        } else if springboard.buttons["Not Now"].exists {
            springboard.buttons["Not Now"].tap()
        }
    }

    private func allowNotificationsIfAsked(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 4) {
            springboard.buttons["Allow"].tap()
        }
    }

    /// Settings is wherever the user's navigation layout put it: a tab, or behind "More".
    private func openSettings(_ app: XCUIApplication) throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Did not reach the logged-in app")
        let tab = app.tabBars.buttons["Settings"]
        if tab.exists {
            tab.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        if more.exists {
            more.tap()
            let link = app.buttons["Settings"].firstMatch
            if link.waitForExistence(timeout: 3) {
                link.tap()
                return
            }
        }
        // Top-left bar menu.
        let menu = app.navigationBars.buttons.firstMatch
        menu.tap()
        let item = app.buttons["Settings"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Could not find Settings")
        item.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

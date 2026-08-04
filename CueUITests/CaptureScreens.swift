import XCTest

/// Captures prompter screenshots as test attachments for visual review.
final class CaptureScreens: XCTestCase {

    /// App Store screenshots. Captures the real screens — no mockups — with
    /// the reading cursor placed partway through so the spoken / current /
    /// upcoming word states are all visible.
    func testCaptureForAppStore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "14"]
        app.launch()

        attach(XCUIScreen.main.screenshot(), named: "01-setup")

        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "02-prompter")

        app.buttons["Prompter settings"].tap()
        XCTAssertTrue(app.staticTexts["Reading line"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "03-settings")
        app.buttons["Done"].tap()

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "04-landscape")
        XCUIDevice.shared.orientation = .portrait

        app.buttons["Exit"].tap()
        XCTAssertTrue(app.buttons["How On Cue works"].waitForExistence(timeout: 5))
        app.buttons["How On Cue works"].tap()
        XCTAssertTrue(app.staticTexts["The script follows your voice"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "05-help")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCapturePrompter() throws {
        let app = XCUIApplication()
        // The simulator has no camera; without this the capture-permission
        // prompt would block the run.
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()

        // The setup screen matters visually too: the start button has to be
        // reachable without scrolling on every screen size.
        XCTAssertTrue(app.buttons["Start prompting →"].waitForExistence(timeout: 5))
        let setupShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        setupShot.name = "setup"
        setupShot.lifetime = .keepAlways
        add(setupShot)

        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "prompter"
        shot.lifetime = .keepAlways
        add(shot)

        // Landscape lays the controls out as a side rail rather than a bar.
        XCUIDevice.shared.orientation = .landscapeLeft
        _ = app.buttons["Listen"].waitForExistence(timeout: 5)
        let landscapeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeShot.name = "prompter-landscape"
        landscapeShot.lifetime = .keepAlways
        add(landscapeShot)
        XCUIDevice.shared.orientation = .portrait
    }
}

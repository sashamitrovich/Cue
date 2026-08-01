import XCTest

/// Captures prompter screenshots as test attachments for visual review.
final class CaptureScreens: XCTestCase {
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
    }
}

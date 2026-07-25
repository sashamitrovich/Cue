import XCTest

/// Captures prompter screenshots as test attachments for visual review.
final class CaptureScreens: XCTestCase {
    func testCapturePrompter() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "prompter"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

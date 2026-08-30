import XCTest

/// Raw material for App Store marketing screenshots — real screens, no
/// mockups. Headline text is composited on afterward; this only captures
/// the app states that make the case for each headline.
final class MarketingCaptures: XCTestCase {

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// It listens: cursor placed mid-script so spoken / active / upcoming
    /// word states are all visible, as if mid-take.
    func testListening() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "18"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-listening")
    }

    /// Mirrors for a teleprompter rig.
    func testMirroring() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "58", "-uiTestingMirrorOn"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-mirroring")
    }

    /// The pre-roll leader.
    func testLeader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "18", "-uiTestingShowCountdown"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-leader")
    }

    /// Records straight from the phone, camera badge and all.
    func testRecording() throws {
        let app = XCUIApplication()
        // A different point in the script from the listening shot: two frames
        // of the same paragraph read as a duplicate in the App Store set.
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "96", "-uiTestingShowRecording"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-recording")
    }

    /// Write or open a script — the editor, full-screen and empty of chrome.
    func testEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()
        XCTAssertTrue(app.buttons["Start prompting →"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-editor")
    }
}

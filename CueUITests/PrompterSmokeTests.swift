import XCTest

/// Smoke tests that drive the real UI in the simulator — these exist to
/// catch layout regressions (like controls being pushed off-screen) that
/// unit tests can't see.
final class PrompterSmokeTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testPrompterControlsAreOnScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let startButton = app.buttons["Start prompting →"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Setup screen should show the start button")
        startButton.tap()

        let listen = app.buttons["Listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 5), "Prompter should show the Listen button")
        XCTAssertTrue(listen.isHittable, "Listen button must be tappable (on-screen, not clipped or covered)")

        let restart = app.buttons["Restart"]
        XCTAssertTrue(restart.exists && restart.isHittable, "Restart button must be visible and tappable")

        let manual = app.buttons["Manual"]
        XCTAssertTrue(manual.exists && manual.isHittable, "Manual button must be visible and tappable")

        let exit = app.buttons["Exit"]
        XCTAssertTrue(exit.exists, "Exit control must be visible")

        // All bottom controls must sit within the visible window bounds.
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(listen.frame), "Listen button frame must be inside the window")
        XCTAssertTrue(window.contains(restart.frame), "Restart button frame must be inside the window")
    }

    func testExitReturnsToSetup() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        app.buttons["Exit"].tap()
        XCTAssertTrue(app.buttons["Start prompting →"].waitForExistence(timeout: 5), "Exit should return to the setup screen")
    }
}

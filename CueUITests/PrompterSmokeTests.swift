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
        // The simulator has no camera; without this the capture-permission
        // prompt would block the run.
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()

        let startButton = app.buttons["Start prompting →"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Setup screen should show the start button")
        // It must be reachable without scrolling — the script editor is sized
        // to leave room for it rather than pushing it below the fold.
        XCTAssertTrue(startButton.isHittable, "Start button must be on screen without scrolling")
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(startButton.frame),
            "Start button frame must be inside the window without scrolling"
        )
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
        // The simulator has no camera; without this the capture-permission
        // prompt would block the run.
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()

        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        app.buttons["Exit"].tap()
        XCTAssertTrue(app.buttons["Start prompting →"].waitForExistence(timeout: 5), "Exit should return to the setup screen")
    }

    /// Landscape moves the take controls from a bottom bar to a side rail.
    /// The failure this guards against is a bar that keeps eating the little
    /// vertical space landscape has, or controls landing off-screen entirely.
    func testControlsStayOnScreenInLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let listen = app.buttons["Listen"]
        let restart = app.buttons["Restart"]
        let manual = app.buttons["Manual"]
        XCTAssertTrue(listen.waitForExistence(timeout: 5), "Listen must survive rotation")
        let window = app.windows.firstMatch.frame
        for control in [listen, restart, manual] {
            XCTAssertTrue(control.isHittable, "\(control.label) must be tappable in landscape")
            XCTAssertTrue(window.contains(control.frame), "\(control.label) must be inside the window in landscape")
        }

        // The rail is a column: the controls share a horizontal band and are
        // stacked vertically, rather than spread across the bottom.
        XCTAssertLessThan(
            abs(listen.frame.midX - restart.frame.midX), 12,
            "controls should be stacked in a side rail, not spread along the bottom"
        )
        XCTAssertGreaterThan(
            abs(listen.frame.midY - restart.frame.midY), 20,
            "controls should be separated vertically in the rail"
        )
        // And the rail must not be eating the middle of the screen.
        XCTAssertTrue(
            listen.frame.midX < window.width * 0.25 || listen.frame.midX > window.width * 0.75,
            "the rail belongs against a side edge"
        )
    }

    /// The reading line has to sit ON the word being read, not above or below
    /// it. This is the defect that eyeballing screenshots kept missing: the
    /// script rendered fine, it was just a line out of register.
    func testReadingLineSitsOnTheWordBeingRead() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

            let line = app.otherElements["readingLine"]
            XCTAssertTrue(line.waitForExistence(timeout: 5), "reading line must exist in \(orientation.rawValue)")
            let firstWord = app.staticTexts["Welcome,"]
            XCTAssertTrue(firstWord.waitForExistence(timeout: 5), "first word must be on screen in \(orientation.rawValue)")

            let drift = abs(line.frame.midY - firstWord.frame.midY)
            XCTAssertLessThan(
                drift, 26,
                "reading line \(line.frame) vs word \(firstWord.frame) — off by \(Int(drift))pt "
                + "in window \(app.windows.firstMatch.frame) (orientation \(orientation.rawValue))"
            )
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// Every take control must be fully on screen in landscape — the rail was
    /// taller than the screen, so the last button was clipped off the bottom.
    func testAllControlsFitInTheLandscapeRail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        let window = app.windows.firstMatch.frame
        for name in ["Restart", "Listen", "Manual"] {
            let control = app.buttons[name]
            XCTAssertTrue(control.exists, "\(name) must exist in landscape")
            XCTAssertTrue(
                window.contains(control.frame),
                "\(name) is clipped: frame \(control.frame) is not inside window \(window)"
            )
            XCTAssertTrue(control.isHittable, "\(name) must be tappable in landscape")
        }
    }
}

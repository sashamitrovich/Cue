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
        XCTAssertTrue(listen.waitForExistence(timeout: 5), "Listen must survive rotation")
        let window = app.windows.firstMatch.frame
        for control in [listen, restart] {
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
            let firstWord = app.staticTexts["Being"]
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
        for name in ["Restart", "Listen"] {
            let control = app.buttons[name]
            XCTAssertTrue(control.exists, "\(name) must exist in landscape")
            XCTAssertTrue(
                window.contains(control.frame),
                "\(name) is clipped: frame \(control.frame) is not inside window \(window)"
            )
            XCTAssertTrue(control.isHittable, "\(name) must be tappable in landscape")
        }
    }

    /// The script must not run underneath the landscape rail, and must not be
    /// sliced off by the notch inset on the opposite side. Both happened once
    /// the prompter went full-bleed and the script stopped padding for the
    /// safe area itself.
    func testScriptClearsTheRailAndTheSafeAreaInLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        let rail = app.buttons["Listen"].frame
        let window = app.windows.firstMatch.frame

        // Words that appear exactly once in the default script — a repeated
        // word makes the query ambiguous rather than the layout wrong.
        for label in ["inquired", "didactic,", "beseechingly,"] {
            let word = app.staticTexts.matching(identifier: label).firstMatch
            guard word.exists else { continue }
            XCTAssertFalse(
                word.frame.intersects(rail),
                "\(label) at \(word.frame) overlaps the control rail at \(rail)"
            )
            XCTAssertTrue(
                window.insetBy(dx: -1, dy: -1).contains(word.frame),
                "\(label) at \(word.frame) runs outside the window \(window)"
            )
        }
    }

    /// Rotating back and forth must not leave the script out of register.
    /// Rotation produces transient layouts, and a stale measurement taken
    /// during one of them used to leave the script floating with the opening
    /// line scrolled off the top.
    func testAlignmentSurvivesRepeatedRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        let sequence: [UIDeviceOrientation] = [.landscapeLeft, .portrait, .landscapeRight, .portrait]
        for orientation in sequence {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))
        }
        defer { XCUIDevice.shared.orientation = .portrait }

        let line = app.otherElements["readingLine"]
        let firstWord = app.staticTexts.matching(identifier: "Being").firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(
            firstWord.waitForExistence(timeout: 5),
            "the opening line must still be on screen after rotating back and forth"
        )

        let window = app.windows.firstMatch.frame
        XCTAssertTrue(
            window.contains(firstWord.frame),
            "opening line at \(firstWord.frame) drifted outside the window \(window)"
        )
        let drift = abs(line.frame.midY - firstWord.frame.midY)
        XCTAssertLessThan(drift, 26, "after rotating back and forth the line is \(Int(drift))pt off the word")
    }

    /// Finds a settings slider, scrolling the sheet if the section it lives in
    /// has been pushed below the fold. Asserting on a fixed position breaks
    /// every time a setting is added above it — which is exactly what adding
    /// the "Read text" slider did.
    @discardableResult
    private func revealSlider(named name: String, in app: XCUIApplication) -> XCUIElement {
        let slider = app.sliders[name]
        // The settings sheet is a SwiftUI Form, which is lazy: a row below the
        // fold is not merely off-screen, it does not exist in the tree yet.
        // Swiping the app itself doesn't scroll it — the scrollable element
        // has to be the one that gets the gesture.
        let scroller = [app.collectionViews.firstMatch, app.tables.firstMatch, app.scrollViews.firstMatch]
            .first { $0.exists } ?? app
        // Generous, because how many drags this needs depends on how many rows
        // the sheet shows at once — and Prompter settings is now a partial
        // sheet (a single ~45% detent, so the script stays visible while you
        // adjust it), which is about half of what it used to be. At 10 this
        // helper passed three full runs in four and failed the fourth.
        for _ in 0..<24 {
            if slider.exists && slider.isHittable { return slider }
            // Short drags, not swipes: a full swipe scrolls straight past the
            // row. Held near the left edge so the gesture can never land on a
            // slider thumb and change a value on the way past.
            let from = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.72))
            let to = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.52))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        return slider
    }

    /// Dragging a control must visibly change the script — in BOTH
    /// orientations. This is the assertion that was missing: the side-margin
    /// setting was implemented as a floor over the safe-area inset, so in
    /// landscape, where that inset is ~47pt a side, most of the slider's
    /// range did nothing at all. Unit tests passed the whole time, because
    /// they asserted the rule I intended rather than the effect you see.
    func testSideMarginMovesTheScriptInBothOrientations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        app.launch()
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))

            let word = app.staticTexts.matching(identifier: "Being").firstMatch
            XCTAssertTrue(word.waitForExistence(timeout: 5))
            let narrow = word.frame.minX

            app.buttons["Prompter settings"].tap()
            let slider = revealSlider(named: "Side margins", in: app)
            XCTAssertTrue(slider.exists && slider.isHittable, "margin slider must be reachable")
            // Deliberately a SMALL increase. A first version of this test used
            // 0.9, which passed even against the broken rule: at that end the
            // margin exceeds the ~47pt landscape inset and does move the
            // text. The defect lived in the bottom of the range.
            slider.adjust(toNormalizedSliderPosition: 0.25)
            app.buttons["Done"].tap()

            XCTAssertTrue(word.waitForExistence(timeout: 5))
            let wide = word.frame.minX
            XCTAssertGreaterThan(
                wide, narrow + 4,
                "widening the margin must move the script inward "
                + "(orientation \(orientation.rawValue): \(narrow) -> \(wide))"
            )

            // Put it back, so the next orientation starts from a known place.
            app.buttons["Prompter settings"].tap()
            revealSlider(named: "Side margins", in: app).adjust(toNormalizedSliderPosition: 0.0)
            app.buttons["Done"].tap()
        }
        XCUIDevice.shared.orientation = .portrait
    }
}

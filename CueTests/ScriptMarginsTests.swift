import XCTest
@testable import Cue

final class ScriptMarginsTests: XCTestCase {

    func testMarginActsAsAFloorOverTheSafeArea() {
        // A phone with no cutout: the chosen margin is what you get.
        XCTAssertEqual(ScriptMargins.inset(safeArea: 0, margin: 16), 16)
        XCTAssertEqual(ScriptMargins.inset(safeArea: 0, margin: 64), 64)
    }

    func testSafeAreaWinsWhenItIsLarger() {
        // Landscape notch side: content cannot be drawn under the cutout,
        // however narrow the reader sets the margins.
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 8), 47)
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 16), 47)
    }

    func testTheTwoAreNeverAdded() {
        // Adding them is the bug this rule replaced: 47 + 26 cost the script
        // ~73pt a side in landscape.
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 26), 47)
        XCTAssertNotEqual(ScriptMargins.inset(safeArea: 47, margin: 26), 73)
    }

    func testAWiderMarginStillWidensTheNotchSide() {
        // Past the inset the reader's choice takes over again, so the control
        // does something on every side of every device.
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 80), 80)
    }

    func testTheRailIsAddedOnTopOfTheMargin() {
        // The rail is occupied space, not a margin — text must clear both.
        XCTAssertEqual(ScriptMargins.inset(safeArea: 0, margin: 16, rail: 56), 72)
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 16, rail: 56), 103)
    }

    func testNegativeInputsCannotPullTextOffScreen() {
        XCTAssertEqual(ScriptMargins.inset(safeArea: -10, margin: -10), 0)
        XCTAssertEqual(ScriptMargins.inset(safeArea: 0, margin: 16, rail: -5), 16)
    }

    func testTheOfferedRangeIsSaneAndContainsTheDefault() {
        XCTAssertTrue(ScriptMargins.range.contains(ScriptMargins.default))
        XCTAssertGreaterThan(ScriptMargins.range.lowerBound, 0,
                             "text should never be flush against the glass")
    }
}

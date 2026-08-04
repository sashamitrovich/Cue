import XCTest
@testable import Cue

final class ScriptMarginsTests: XCTestCase {

    func testTheMarginAlwaysChangesTheInset() {
        // The defect this replaced: as a floor, every value below the ~47pt
        // landscape safe-area inset did nothing, so the slider felt dead.
        let noCutout = (0...4).map { ScriptMargins.inset(safeArea: 0, margin: CGFloat($0) * 20) }
        let notchSide = (0...4).map { ScriptMargins.inset(safeArea: 47, margin: CGFloat($0) * 20) }
        XCTAssertEqual(noCutout, noCutout.sorted())
        XCTAssertEqual(notchSide, notchSide.sorted())
        XCTAssertEqual(Set(noCutout).count, 5, "every step must move the text")
        XCTAssertEqual(Set(notchSide).count, 5, "including on the notch side")
    }

    func testSafeAreaIsAlwaysHonouredUnderneath() {
        // Content can never be drawn under a cutout, whatever the margin.
        XCTAssertGreaterThanOrEqual(ScriptMargins.inset(safeArea: 47, margin: 0), 47)
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 20), 67)
    }

    func testTextIsNeverFlushAgainstTheGlass() {
        // A phone with no cutout reports zero insets — an iPhone SE in
        // landscape is the case that catches a pure safe-area rule.
        XCTAssertGreaterThanOrEqual(ScriptMargins.inset(safeArea: 0, margin: 0),
                                    ScriptMargins.minimumGap)
    }

    func testTheRailIsAddedOnTop() {
        // The rail is occupied space, not a margin — text must clear both.
        XCTAssertEqual(ScriptMargins.inset(safeArea: 0, margin: 8, rail: 56), 72)
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 8, rail: 56), 111)
    }

    func testNegativeInputsCannotPullTextOffScreen() {
        XCTAssertEqual(ScriptMargins.inset(safeArea: -10, margin: -10), ScriptMargins.minimumGap)
        XCTAssertEqual(ScriptMargins.inset(safeArea: 0, margin: 8, rail: -5), 16)
    }

    func testTheOfferedRangeContainsTheDefault() {
        XCTAssertTrue(ScriptMargins.range.contains(ScriptMargins.default))
    }
}

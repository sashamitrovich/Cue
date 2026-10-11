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

    // #24: at the maximum on a wide Mac window the text barely moved in,
    // because the margin was a point value sized for a phone. The maximum is
    // now a narrow column in the middle, under the lens.
    func testTheMaximumIsANarrowCentreColumnOnAWideWindow() {
        let width: CGFloat = 1400
        let side = ScriptMargins.inset(safeArea: 0, margin: ScriptMargins.range.upperBound,
                                       width: width, fontSize: 40)
        XCTAssertEqual(width - 2 * side, width * ScriptMargins.narrowestShare, accuracy: 0.001)
    }

    // The defect this replaced: the column was clamped to a fixed minimum, so
    // on an upright iPhone at a large font the slider stopped doing anything
    // part-way along. Every step must now narrow the column, on every screen.
    func testEveryStepNarrowsTheColumnOnEveryScreen() {
        let steps = stride(from: CGFloat(0), through: ScriptMargins.range.upperBound, by: 4)
        for width in stride(from: CGFloat(320), through: 2000, by: 40) {
            for fontSize in stride(from: CGFloat(16), through: 80, by: 8) {
                // Side safe areas and the rail only occur sideways, where the
                // screen is at least 568pt wide.
                let sides: [(CGFloat, CGFloat)] = width < 568
                    ? [(0, 0)] : [(0, 0), (62, 0), (0, 56), (62, 56)]
                for (safeArea, rail) in sides {
                    let columns = steps.map { margin -> CGFloat in
                        let side = ScriptMargins.inset(safeArea: safeArea, margin: margin, rail: rail,
                                                       width: width, fontSize: fontSize)
                        return width - 2 * side
                    }
                    for (wider, narrower) in zip(columns, columns.dropFirst()) {
                        XCTAssertLessThan(narrower, wider,
                            "dead step at width \(width), font \(fontSize), safe area \(safeArea), rail \(rail)")
                    }
                }
            }
        }
    }

    func testTheMaximumOnAnUprightIPhoneIsAReadableColumn() {
        // iPhone 15 Pro upright, large font: the column at 100% leaves room
        // for a long word, and is narrower than at 50%.
        let full = 393 - 2 * ScriptMargins.inset(safeArea: 0, margin: 80, width: 393, fontSize: 48)
        let half = 393 - 2 * ScriptMargins.inset(safeArea: 0, margin: 40, width: 393, fontSize: 48)
        XCTAssertEqual(full, 393 * ScriptMargins.widestShare, accuracy: 0.001)
        XCTAssertGreaterThan(half, full)
    }

    func testTheLabelIsAPercentOfTheRange() {
        XCTAssertEqual(ScriptMargins.percent(0), 0)
        XCTAssertEqual(ScriptMargins.percent(4), 5)
        XCTAssertEqual(ScriptMargins.percent(8), 10)
        XCTAssertEqual(ScriptMargins.percent(80), 100)
        XCTAssertEqual(ScriptMargins.percent(200), 100)
    }

    func testTheRailAndSafeAreaAreNotScaled() {
        XCTAssertEqual(ScriptMargins.inset(safeArea: 47, margin: 0, rail: 56, width: 1400), 47 + 56)
    }
}

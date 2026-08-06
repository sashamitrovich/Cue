import XCTest
@testable import Cue

final class VisualLinesTests: XCTestCase {

    /// Three drawn rows of three words, as a wrapped paragraph produces.
    private func threeRows() -> [Int: CGRect] {
        var frames: [Int: CGRect] = [:]
        for row in 0..<3 {
            for column in 0..<3 {
                let id = row * 3 + column
                frames[id] = CGRect(x: CGFloat(column) * 100, y: CGFloat(row) * 40, width: 90, height: 34)
            }
        }
        return frames
    }

    func testWordsAreGroupedIntoTheRowsTheyAreDrawnOn() {
        let rows = VisualLines.rows(from: threeRows())
        XCTAssertEqual(rows, [[0, 1, 2], [3, 4, 5], [6, 7, 8]])
    }

    func testSteppingBackGoesOneDrawnRowNotOneParagraph() {
        // The defect this replaced: stepping by typed line moved a whole
        // wrapped paragraph, because a paragraph is one typed line.
        let target = VisualLines.wordStepping(-1, from: 7, frames: threeRows())
        XCTAssertEqual(target, 3, "should land on the first word of the row above")
    }

    func testSteppingForward() {
        XCTAssertEqual(VisualLines.wordStepping(1, from: 1, frames: threeRows()), 3)
    }

    func testItLandsOnTheStartOfTheRow() {
        // Resuming mid-phrase would be worse than not moving at all.
        XCTAssertEqual(VisualLines.wordStepping(-1, from: 8, frames: threeRows()), 3)
        XCTAssertEqual(VisualLines.wordStepping(-2, from: 8, frames: threeRows()), 0)
    }

    func testClampsAtBothEnds() {
        XCTAssertEqual(VisualLines.wordStepping(-5, from: 4, frames: threeRows()), 0)
        XCTAssertEqual(VisualLines.wordStepping(5, from: 4, frames: threeRows()), 6)
    }

    func testUnevenBaselinesStillCountAsOneRow() {
        // Descenders and mixed word heights mean a row is never perfectly level.
        var frames = threeRows()
        frames[1] = CGRect(x: 100, y: 3, width: 90, height: 34)
        frames[2] = CGRect(x: 200, y: -2, width: 90, height: 34)
        XCTAssertEqual(VisualLines.rows(from: frames).first, [0, 1, 2])
    }

    func testNoMeasurementsMeansNoGuess() {
        // Better to leave the cursor alone than to move it somewhere invented.
        XCTAssertNil(VisualLines.wordStepping(-1, from: 3, frames: [:]))
        XCTAssertTrue(VisualLines.rows(from: [:]).isEmpty)
    }

    func testACursorBetweenMeasuredWordsStillResolves() {
        var frames = threeRows()
        frames[4] = nil                       // a word that hasn't been measured
        XCTAssertNotNil(VisualLines.wordStepping(-1, from: 4, frames: frames))
    }
}

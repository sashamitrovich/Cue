import XCTest
@testable import Cue

/// #26: a 3-second pre-roll showed 4 first, a 10-second one 11.
final class PreRollTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testTheCountdownStartsAtTheSetNumber() {
        for seconds in [3, 5, 10] {
            let deadline = start.addingTimeInterval(Double(seconds))
            XCTAssertEqual(PreRoll.remaining(until: deadline, at: start), seconds)
        }
    }

    func testEachNumberLastsOneSecond() {
        let deadline = start.addingTimeInterval(3)
        XCTAssertEqual(PreRoll.remaining(until: deadline, at: start.addingTimeInterval(0.99)), 3)
        XCTAssertEqual(PreRoll.remaining(until: deadline, at: start.addingTimeInterval(1.0)), 2)
        XCTAssertEqual(PreRoll.remaining(until: deadline, at: start.addingTimeInterval(2.5)), 1)
    }

    func testItNeverShowsZero() {
        let deadline = start.addingTimeInterval(3)
        XCTAssertEqual(PreRoll.remaining(until: deadline, at: deadline), 1)
    }
}

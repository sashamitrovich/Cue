import XCTest
@testable import Cue

/// The word-space smoothing that drives the prompter's highlight and scroll.
/// `ScrollState.advance` glides the displayed position toward the raw
/// recognition cursor, so a burst of recognised words reads as continuous
/// motion rather than a jump.
final class ScrollStateTests: XCTestCase {

    private func advance(
        _ position: Double, toward cursor: Double,
        dt: Double = 1.0 / 60, tau: Double = 0.25,
        jumped: Bool = false, snapDistance: Double = 16
    ) -> Double {
        ScrollState.advance(
            position: position, toward: cursor, dt: dt, tau: tau,
            jumped: jumped, snapDistance: snapDistance
        )
    }

    func testGlidesTowardTheCursor() {
        // A gap is closed fractionally over time, not all at once.
        let next = advance(0, toward: 4)
        XCTAssertGreaterThan(next, 0)
        XCTAssertLessThan(next, 4)
    }

    func testNeverOvershoots() {
        // A huge frame must not carry the position past the cursor.
        XCTAssertEqual(advance(0, toward: 0.4, dt: 10), 0.4, accuracy: 0.0001)
    }

    func testSilenceIsStillness() {
        // On the cursor already, nothing moves, however long the frame.
        XCTAssertEqual(advance(5, toward: 5, dt: 10), 5)
    }

    func testADeliberateMoveSnaps() {
        XCTAssertEqual(advance(5, toward: 3, jumped: true), 3)
        XCTAssertEqual(advance(5, toward: 30, jumped: true), 30)
    }

    func testAFarReAnchorSnaps() {
        // A re-anchor past the snap distance goes straight there rather than
        // gliding word by word.
        XCTAssertEqual(advance(5, toward: 40, snapDistance: 16), 40)
    }

    func testABackwardCursorSnaps() {
        // A backward cursor is a deliberate move (voice command, restart) and
        // the display follows at once rather than gliding back.
        XCTAssertEqual(advance(10, toward: 4), 4)
    }

    func testConvergesMonotonicallyTowardTheCursor() {
        var p = 0.0
        for _ in 0..<600 {
            let next = advance(p, toward: 8)
            XCTAssertGreaterThanOrEqual(next, p)
            XCTAssertLessThanOrEqual(next, 8)
            p = next
        }
        XCTAssertEqual(p, 8, accuracy: 0.01)
    }

    func testLargerTauIsSlower() {
        // A longer time constant moves less in one frame.
        let fast = advance(0, toward: 8, tau: 0.1)
        let slow = advance(0, toward: 8, tau: 1.0)
        XCTAssertGreaterThan(fast, slow)
    }
}

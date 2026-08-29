import XCTest
@testable import Cue

final class ScrollPursuitTests: XCTestCase {

    private let snap: CGFloat = 900

    // MARK: - Speed

    func testSpeedFollowsThePaceAndTheLayout() {
        // 120 wpm is two words a second; 30pt per word is 60pt/s, and the
        // catch-up multiplier is applied on top.
        let speed = ScrollPursuit.speed(
            pointsPerWord: 30, wordsPerMinute: 120, catchUp: 1.3, minimum: 40
        )
        XCTAssertEqual(speed, 78, accuracy: 0.001)
    }

    func testSpeedFallsBackToTheFloorBeforeThereIsAnythingToMeasure() {
        // The opening words of a take: no measured pace, no usable spacing.
        XCTAssertEqual(
            ScrollPursuit.speed(pointsPerWord: 0, wordsPerMinute: 140, catchUp: 1.3, minimum: 40), 40
        )
        XCTAssertEqual(
            ScrollPursuit.speed(pointsPerWord: 30, wordsPerMinute: 0, catchUp: 1.3, minimum: 40), 40
        )
        // A very slow reader must not scroll slower than the floor either.
        XCTAssertEqual(
            ScrollPursuit.speed(pointsPerWord: 2, wordsPerMinute: 10, catchUp: 1.3, minimum: 40), 40
        )
    }

    // MARK: - Stepping

    func testTheTargetTravelsRatherThanTeleporting() {
        // A burst of recognition put the cursor 100pt ahead. One 60fps frame
        // at 78pt/s covers 1.3pt of that — not the whole 100.
        let next = ScrollPursuit.step(
            target: 0, toward: -100, speed: 78, dt: 1.0 / 60, snapDistance: snap, jumped: false
        )
        XCTAssertEqual(next, -1.3, accuracy: 0.001)
    }

    func testABurstIsSpreadOverRoughlyTheTimeItTookToSay() {
        // Five words at 120 wpm is 2.5 seconds of speech, and at 30pt a word
        // the script has 150pt to cover. With a 1.3x catch-up it should take
        // a bit under that — bounded, continuous, and never instant.
        let speed = ScrollPursuit.speed(
            pointsPerWord: 30, wordsPerMinute: 120, catchUp: 1.3, minimum: 40
        )
        var target: CGFloat = 0
        var elapsed = 0.0
        let dt = 1.0 / 60
        // -149.5, not -150: sub-half-point moves are deliberately not made,
        // so the target parks just short rather than landing exactly.
        while target > -149.5 && elapsed < 10 {
            target = ScrollPursuit.step(
                target: target, toward: -150, speed: speed, dt: dt, snapDistance: snap, jumped: false
            )
            elapsed += dt
        }
        XCTAssertEqual(elapsed, 2.5 / 1.3, accuracy: 0.1)
    }

    func testItStopsOnArrivalRatherThanOvershooting() {
        // A step larger than the remaining distance must land exactly, or the
        // script would oscillate around the reading line forever.
        let next = ScrollPursuit.step(
            target: 0, toward: -1.0, speed: 1000, dt: 1.0 / 60, snapDistance: snap, jumped: false
        )
        XCTAssertEqual(next, -1.0, accuracy: 0.0001)
    }

    func testSilenceDoesNotMoveTheScript() {
        // The core of the "no drift" requirement: with the target already on
        // the cursor, no amount of elapsed time moves it. Recognition
        // delivering nothing new means the script is completely still.
        var target: CGFloat = -420
        for _ in 0..<600 {
            target = ScrollPursuit.step(
                target: target, toward: -420, speed: 500, dt: 1.0 / 60, snapDistance: snap, jumped: false
            )
        }
        XCTAssertEqual(target, -420)
    }

    func testADeliberateMoveIsNotPaced() {
        // Restart, a drag, a voice command: walking there at speaking pace
        // would take as long as reading the script.
        XCTAssertEqual(
            ScrollPursuit.step(
                target: -5000, toward: 0, speed: 78, dt: 1.0 / 60, snapDistance: snap, jumped: true
            ),
            0
        )
    }

    func testAnImplausiblyLargeGapGoesDirectly() {
        // Nothing spoken moves the script 5000pt; this is a rotation or a
        // relayout, and pacing it would crawl for a minute.
        XCTAssertEqual(
            ScrollPursuit.step(
                target: 0, toward: -5000, speed: 78, dt: 1.0 / 60, snapDistance: snap, jumped: false
            ),
            -5000
        )
    }

    func testItIsFrameRateIndependent() {
        // The same elapsed time must cover the same distance whether it
        // arrives as one long frame or several short ones.
        let speed: CGFloat = 78
        let oneStep = ScrollPursuit.step(
            target: 0, toward: -1000, speed: speed, dt: 0.1, snapDistance: 2000, jumped: false
        )
        var many: CGFloat = 0
        for _ in 0..<6 {
            many = ScrollPursuit.step(
                target: many, toward: -1000, speed: speed, dt: 0.1 / 6, snapDistance: 2000, jumped: false
            )
        }
        XCTAssertEqual(oneStep, many, accuracy: 0.001)
    }

    func testBackwardMovementIsPacedToo() {
        // "Scroll up" without the jump flag, or a cursor correction: the
        // script travels back at the same bounded speed.
        let next = ScrollPursuit.step(
            target: -100, toward: 0, speed: 78, dt: 1.0 / 60, snapDistance: snap, jumped: false
        )
        XCTAssertEqual(next, -100 + 1.3, accuracy: 0.001)
    }
}

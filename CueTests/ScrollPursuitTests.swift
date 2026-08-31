import XCTest
@testable import Cue

final class ScrollPursuitTests: XCTestCase {

    private let snap: CGFloat = 900

    // MARK: - Speed

    private func speed(gap: CGFloat, pointsPerWord: CGFloat = 30, wpm: Double = 120) -> CGFloat {
        ScrollPursuit.speed(
            gap: gap, pointsPerWord: pointsPerWord, wordsPerMinute: wpm,
            response: 0.18, maxCatchUp: 4, minimum: 40
        )
    }

    func testSpeedIsCappedAtAMultipleOfTheSpeakingPace() {
        // 120 wpm at 30pt a word is 60pt/s; the ceiling is 4x that. A large
        // gap must not be covered instantly — that is the jump this whole
        // type exists to prevent.
        XCTAssertEqual(speed(gap: -400), 240, accuracy: 0.001)
    }

    func testSpeedScalesWithTheGapBelowTheCeiling() {
        // 20pt over a 0.18s response is 111pt/s, under the 240 ceiling, so
        // the proportional term governs and the script eases in.
        XCTAssertEqual(speed(gap: -20), 20 / 0.18, accuracy: 0.001)
    }

    func testTheGapActuallyCloses() {
        // The point of the ceiling being well above 1x pace. At 4x, a target
        // that is behind gains on the reader at 3x pace; at the old 1.3x it
        // gained at 0.3x, so the script never caught up and the active word
        // sat permanently below the reading line.
        let pace: CGFloat = 30 * CGFloat(120.0 / 60)
        XCTAssertGreaterThan(speed(gap: -400), pace * 2, "must gain on the speaker, not merely keep up")
    }

    func testSpeedFallsBackToTheFloorBeforeThereIsAnythingToMeasure() {
        // The opening words of a take: no measured pace, no usable spacing,
        // and a gap too small for the proportional term to clear the floor.
        XCTAssertEqual(speed(gap: -1, pointsPerWord: 0), 40)
        XCTAssertEqual(speed(gap: -1, wpm: 0), 40)
        // A very slow reader must not scroll slower than the floor either.
        XCTAssertEqual(speed(gap: -1, pointsPerWord: 2, wpm: 10), 40)
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
        // Five words at 120 wpm is 2.5 seconds of speech and, at 30pt a word,
        // 150pt of script. It must be recovered in well under that — the
        // reader is still talking — but spread over enough frames to read as
        // movement rather than a jump.
        var target: CGFloat = 0
        var elapsed = 0.0
        let dt = 1.0 / 60
        // -149.5, not -150: sub-half-point moves are deliberately not made,
        // so the target parks just short rather than landing exactly.
        while target > -149.5 && elapsed < 10 {
            target = ScrollPursuit.step(
                target: target,
                toward: -150,
                speed: speed(gap: -150 - target),
                dt: dt,
                snapDistance: snap,
                jumped: false
            )
            elapsed += dt
        }
        XCTAssertLessThan(elapsed, 2.5, "must gain on the speaker rather than fall further behind")
        XCTAssertGreaterThan(elapsed, 4 * dt, "must not be covered in a couple of frames")
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

    // MARK: - How long a recogniser burst takes to land

    /// Seconds for the target to get within `within` of `gap`, at 60fps.
    ///
    /// Deliberately not "to arrive": the last stretch is the proportional
    /// term's exponential tail, which takes as long again as the whole
    /// ceiling-bound run and is invisible on screen. What the reader feels is
    /// the script coming back under the reading line, so the threshold
    /// defaults to one word.
    private func secondsToClose(
        gap: CGFloat, within: CGFloat = 30, pointsPerWord: CGFloat = 30, wpm: Double = 120
    ) -> Double {
        var target: CGFloat = 0
        var elapsed: Double = 0
        let dt = 1.0 / 60
        while abs(gap - target) > within, elapsed < 10 {
            target = ScrollPursuit.step(
                target: target,
                toward: gap,
                speed: speed(gap: gap - target, pointsPerWord: pointsPerWord, wpm: wpm),
                dt: dt,
                snapDistance: snap,
                jumped: false
            )
            elapsed += dt
        }
        return elapsed
    }

    func testTheCeilingIsWhatSetsBurstRecoveryTime() {
        // Recognition arrives in bursts of several words, so this is the
        // number the reader actually feels: how long the script stays behind
        // after one partial result lands.
        //
        // 120 wpm at 30pt a word is 60pt/s, so the ceiling is 240pt/s. A
        // five-word burst is 150pt and the proportional term would ask for
        // 833pt/s — the ceiling binds for essentially the whole recovery,
        // which is why the time is gap/ceiling rather than anything to do
        // with `response`.
        // Ceiling-bound from 150pt down to 43.2pt (where the proportional
        // term drops below it), then the tail: about half a second before
        // the script is back within a word of the cursor.
        let fiveWords = secondsToClose(gap: 150)
        XCTAssertEqual(fiveWords, 0.51, accuracy: 0.05)
    }

    func testRecoveryTimeDegradesWhenTheMeasuredPaceFalls() {
        // The regression this branch exists to prove. The ceiling is a
        // multiple of a *pace*, so feeding it a pace that decays — as a
        // whole-take average does across pauses and ad-libs — slows catch-up
        // by the same proportion. At the 60 wpm floor the identical burst
        // takes twice as long as at 120, with nothing about the reader's
        // actual speed at that moment having changed.
        let atPace = secondsToClose(gap: 150, wpm: 120)
        let atFloor = secondsToClose(gap: 150, wpm: 60)
        XCTAssertEqual(atFloor / atPace, 2, accuracy: 0.1)
    }

    func testTheCeilingBindsWithinAWordOrTwo() {
        // Where the ceiling takes over from the proportional term, in words.
        // It is `response * maxCatchUp * wpm/60` and independent of font
        // size — 1.44 words at 120 wpm. So the ceiling is not an outlier
        // guard: it governs ordinary reading.
        let pointsPerWord: CGFloat = 30
        let crossover = 0.18 * 4 * CGFloat(120.0 / 60)
        let justUnder = speed(gap: (crossover - 0.3) * pointsPerWord)
        let justOver = speed(gap: (crossover + 0.3) * pointsPerWord)
        XCTAssertLessThan(justUnder, 240, "below the crossover the gap still sets the speed")
        XCTAssertEqual(justOver, 240, accuracy: 0.001, "above it, the ceiling is all that matters")
    }
}

import XCTest
@testable import Cue

final class ScrollPursuitTests: XCTestCase {

    private let snap: CGFloat = 900

    // MARK: - Speed

    /// The defaults stand in for a real script: a 44pt row pitch, which is
    /// what a 16e measured at the shipping type size, and a ceiling of four
    /// lines a second.
    private func speed(gap: CGFloat, lineHeight: CGFloat = 44, linesPerSecond: CGFloat = 4) -> CGFloat {
        ScrollPursuit.speed(
            gap: gap, lineHeight: lineHeight, maxLinesPerSecond: linesPerSecond,
            response: 0.18, minimum: 40
        )
    }

    func testSpeedIsCappedAtSoManyLinesASecond() {
        // A 44pt row at four lines a second is 176pt/s. A large gap must not
        // be covered instantly — that is the jump this whole type exists to
        // prevent.
        XCTAssertEqual(speed(gap: -400), 176, accuracy: 0.001)
    }

    func testTheCeilingDependsOnTypeSizeAndNothingElse() {
        // The reason the ceiling is expressed in lines: it must follow the
        // reader's type size, and must not move for any other reason. Double
        // the row pitch, double the ceiling — and nothing about the speaking
        // pace, the text's wrapping or how long the take has run appears in
        // it at all, which is what the previous `pointsPerWord * wpm/60` form
        // could not promise.
        XCTAssertEqual(speed(gap: -400, lineHeight: 88), 352, accuracy: 0.001)
        XCTAssertEqual(speed(gap: -400, lineHeight: 22), 88, accuracy: 0.001)
    }

    func testSpeedScalesWithTheGapBelowTheCeiling() {
        // 20pt over a 0.18s response is 111pt/s, under the 176 ceiling, so
        // the proportional term governs and the script eases in.
        XCTAssertEqual(speed(gap: -20), 20 / 0.18, accuracy: 0.001)
    }

    func testTheGapActuallyCloses() {
        // The ceiling has to sit well above the rate a reader generates new
        // script, or the target never catches up and the active word sits
        // permanently below the reading line. A brisk 200 wpm over a 44pt row
        // holding four words is about 3.8 lines... but the reader is not the
        // constraint here: what matters is that catching up outruns falling
        // behind, so the ceiling must beat the pace at which gap accumulates.
        let generatedLinesPerSecond: CGFloat = 200.0 / 60 / 4     // 200 wpm, 4 words a line
        XCTAssertGreaterThan(
            speed(gap: -400), generatedLinesPerSecond * 44 * 2,
            "must gain on the speaker, not merely keep up"
        )
    }

    func testSpeedFallsBackToTheFloorBeforeThereIsAnythingToMeasure() {
        // The opening frames of a take: the layout has not been measured, so
        // there is no line height yet, and the gap is too small for the
        // proportional term to clear the floor.
        XCTAssertEqual(speed(gap: -1, lineHeight: 0), 40)
        XCTAssertEqual(speed(gap: -1, linesPerSecond: 0), 40)
        // A tiny type size must not scroll slower than the floor either.
        XCTAssertEqual(speed(gap: -1, lineHeight: 2, linesPerSecond: 1), 40)
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
        // A burst of recognition landed about three and a half rows ahead —
        // roughly two seconds of speech. It must be recovered in well under
        // that — the reader is still talking — but spread over enough frames
        // to read as movement rather than a jump.
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
        gap: CGFloat, within: CGFloat = 44, lineHeight: CGFloat = 44, linesPerSecond: CGFloat = 4
    ) -> Double {
        var target: CGFloat = 0
        var elapsed: Double = 0
        let dt = 1.0 / 60
        while abs(gap - target) > within, elapsed < 10 {
            target = ScrollPursuit.step(
                target: target,
                toward: gap,
                speed: speed(gap: gap - target, lineHeight: lineHeight, linesPerSecond: linesPerSecond),
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
        // A 44pt row at four lines a second is 176pt/s. A 150pt burst — a
        // little over three rows — is entirely ceiling-bound until the last
        // row, because the proportional term would ask for 833pt/s. So the
        // time is gap over ceiling, and nothing to do with `response`.
        let threeRows = secondsToClose(gap: 150)
        XCTAssertEqual(threeRows, (150 - 44) / 176, accuracy: 0.03)
    }

    func testRecoveryTimeIsTheSameNumberOfLinesAtAnyTypeSize() {
        // What the previous form could not do, and the reason for the change.
        // The ceiling used to be a multiple of a *measured pace*, so a pace
        // that decayed — as a whole-take average does across a pause, or
        // while the reader ad-libs and the cursor stalls — slowed catch-up by
        // the same proportion. A take got laggier the longer it ran.
        //
        // Now the only input is the row pitch, so the same gap *measured in
        // rows* recovers in the same time whatever the type size: at double
        // the pitch, a burst twice as tall takes exactly as long.
        let small = secondsToClose(gap: 150, within: 44, lineHeight: 44)
        let large = secondsToClose(gap: 300, within: 88, lineHeight: 88)
        XCTAssertEqual(small, large, accuracy: 0.02)
    }

    func testTheCeilingTakesOverBeforeASingleLine() {
        // Where the ceiling takes over from the proportional term, in rows:
        // `response * linesPerSecond`, which is 0.72 of a row. Anything
        // further behind than three quarters of a line is travelling at the
        // ceiling — so this is not an outlier guard, it is what sets the
        // speed during ordinary reading. Instrumented on a device it was the
        // binding constraint on 20-84% of frames.
        //
        // Worth keeping in view when the constant is tuned: raising it moves
        // this crossover out proportionally.
        let lineHeight: CGFloat = 44
        let crossover: CGFloat = 0.18 * 4
        let justUnder = speed(gap: (crossover - 0.2) * lineHeight)
        let justOver = speed(gap: (crossover + 0.2) * lineHeight)
        XCTAssertLessThan(justUnder, 176, "below the crossover the gap still sets the speed")
        XCTAssertEqual(justOver, 176, accuracy: 0.001, "above it, the ceiling is all that matters")
    }
}

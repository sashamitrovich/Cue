import XCTest
@testable import Cue

final class ReadingPaceTests: XCTestCase {

    // MARK: - Duration estimates

    func testSecondsForWordsAtPace() {
        XCTAssertEqual(ReadingPace.seconds(forWords: 140, wpm: 140), 60, accuracy: 0.001)
        XCTAssertEqual(ReadingPace.seconds(forWords: 70, wpm: 140), 30, accuracy: 0.001)
        XCTAssertEqual(ReadingPace.seconds(forWords: 300, wpm: 150), 120, accuracy: 0.001)
    }

    func testEmptyOrNonsensicalInputEstimatesZero() {
        XCTAssertEqual(ReadingPace.seconds(forWords: 0, wpm: 140), 0)
        XCTAssertEqual(ReadingPace.seconds(forWords: -5, wpm: 140), 0)
        XCTAssertEqual(ReadingPace.seconds(forWords: 100, wpm: 0), 0)
    }

    // MARK: - Measured pace

    func testMeasuredPaceNeedsEnoughWordsAndTime() {
        // Enough time, too few words: the take has barely started.
        XCTAssertNil(ReadingPace.measuredWPM(wordsRead: 5, elapsed: 30))
        // Plenty of words but only a moment of speech — an early burst of
        // recognition results would otherwise report a nonsense pace.
        XCTAssertNil(ReadingPace.measuredWPM(wordsRead: 40, elapsed: 2))
        XCTAssertNotNil(ReadingPace.measuredWPM(wordsRead: 40, elapsed: 20))
    }

    func testMeasuredPaceComputesWordsPerMinute() {
        let wpm = ReadingPace.measuredWPM(wordsRead: 60, elapsed: 30)
        XCTAssertEqual(wpm ?? 0, 120, accuracy: 0.001)
    }

    func testMeasuredPaceIsClampedAgainstLongSilences() {
        // A long pause mid-take drags the raw average toward zero; without a
        // floor the "time left" readout would balloon absurdly.
        let stalled = ReadingPace.measuredWPM(wordsRead: 20, elapsed: 600)
        XCTAssertEqual(stalled ?? 0, 60, accuracy: 0.001)

        let sprinting = ReadingPace.measuredWPM(wordsRead: 1000, elapsed: 60)
        XCTAssertEqual(sprinting ?? 0, 300, accuracy: 0.001)
    }

    func testEffectivePaceFallsBackToBaselineThenSwitchesToMeasured() {
        XCTAssertEqual(
            ReadingPace.effectiveWPM(baseline: 140, wordsRead: 3, elapsed: 2),
            140,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ReadingPace.effectiveWPM(baseline: 140, wordsRead: 60, elapsed: 30),
            120,
            accuracy: 0.001
        )
    }

    // MARK: - Named paces

    func testNamedPacesCoverTheUsefulRange() {
        let values = ReadingPace.namedPaces.map(\.wpm)
        XCTAssertEqual(values, values.sorted(), "presented slowest to fastest")
        for wpm in values {
            XCTAssertTrue(ReadingPace.wpmRange.contains(wpm), "\(wpm) must be reachable from the slider too")
        }
    }

    func testPaceNameSnapsToTheNearestNamedSpeed() {
        XCTAssertEqual(ReadingPace.name(forWPM: 110), "relaxed")
        XCTAssertEqual(ReadingPace.name(forWPM: 140), "natural")
        XCTAssertEqual(ReadingPace.name(forWPM: 165), "brisk")
        // A value nudged by the slider still reads as a word, not a number.
        XCTAssertEqual(ReadingPace.name(forWPM: 132), "natural")
        XCTAssertEqual(ReadingPace.name(forWPM: 200), "brisk")
        XCTAssertEqual(ReadingPace.name(forWPM: 90), "relaxed")
    }

    // MARK: - Formatting

    func testTimeStringFormatting() {
        XCTAssertEqual(ReadingPace.timeString(0), "0:00")
        XCTAssertEqual(ReadingPace.timeString(9), "0:09")
        XCTAssertEqual(ReadingPace.timeString(105), "1:45")
        XCTAssertEqual(ReadingPace.timeString(3750), "1:02:30")
    }

    func testTimeStringHandlesNegativeAndNonFiniteValues() {
        XCTAssertEqual(ReadingPace.timeString(-30), "0:00")
        XCTAssertEqual(ReadingPace.timeString(.infinity), "0:00")
        XCTAssertEqual(ReadingPace.timeString(.nan), "0:00")
    }

    // MARK: - SpeakingClock

    func testClockAccumulatesOnlyWhileRunning() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = SpeakingClock()

        XCTAssertEqual(clock.elapsed(at: t0), 0)
        clock.start(at: t0)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(10)), 10, accuracy: 0.001)

        clock.pause(at: t0.addingTimeInterval(10))
        XCTAssertFalse(clock.isRunning)
        // Paused: time passing must not count toward the take.
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(300)), 10, accuracy: 0.001)

        clock.start(at: t0.addingTimeInterval(300))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(305)), 15, accuracy: 0.001)
    }

    func testRepeatedStartsAndPausesAreIdempotent() {
        let t0 = Date(timeIntervalSince1970: 2_000)
        var clock = SpeakingClock()

        clock.start(at: t0)
        // A second start must not reset the origin and lose elapsed time.
        clock.start(at: t0.addingTimeInterval(5))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(10)), 10, accuracy: 0.001)

        clock.pause(at: t0.addingTimeInterval(10))
        clock.pause(at: t0.addingTimeInterval(20))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(50)), 10, accuracy: 0.001)
    }

    func testResetClearsEverything() {
        let t0 = Date(timeIntervalSince1970: 3_000)
        var clock = SpeakingClock()
        clock.start(at: t0)
        clock.pause(at: t0.addingTimeInterval(42))
        clock.reset()
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(100)), 0)
    }

    func testClockIgnoresBackwardsTime() {
        // Never expected in practice, but a negative interval would silently
        // inflate the measured pace.
        let t0 = Date(timeIntervalSince1970: 4_000)
        var clock = SpeakingClock()
        clock.start(at: t0)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(-30)), 0)
    }
}

final class ScriptProgressTests: XCTestCase {

    private func state(_ text: String) -> TeleprompterState {
        let s = TeleprompterState()
        s.scriptText = text
        s.buildWords()
        return s
    }

    func testWordCountIgnoresWhitespaceAndBlankLines() {
        XCTAssertEqual(TeleprompterState.wordCount(in: "one two three"), 3)
        XCTAssertEqual(TeleprompterState.wordCount(in: "  one \n\n  two \r\n three  "), 3)
        XCTAssertEqual(TeleprompterState.wordCount(in: "   \n  "), 0)
    }

    func testRemainingAndReadSplitAtTheCursor() {
        let s = state("one two three four five")
        XCTAssertEqual(s.wordsRead, 0)
        XCTAssertEqual(s.wordsRemaining, 5)

        s.activeIndex = 2
        // The active word is being said, not yet said.
        XCTAssertEqual(s.wordsRead, 2)
        XCTAssertEqual(s.wordsRemaining, 3)
    }

    func testProgressRunsFromZeroToOne() {
        let s = state("one two three four five")
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
        s.activeIndex = 2
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.001)
        s.activeIndex = 4
        XCTAssertEqual(s.progress, 1.0, accuracy: 0.001)
    }

    func testProgressIsZeroForTrivialScripts() {
        // Guards the divide-by-zero in the width calculation of the progress bar.
        XCTAssertEqual(state("").progress, 0)
        XCTAssertEqual(state("solo").progress, 0)
    }
}

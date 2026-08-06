import XCTest
@testable import Cue

final class VoiceCommandDetectorTests: XCTestCase {

    private var detector: VoiceCommandDetector!

    override func setUp() {
        super.setUp()
        detector = VoiceCommandDetector()
    }

    func testOrdinarySpeechPassesStraightThrough() {
        let result = detector.process(["welcome", "and", "thank", "you"])
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.passthrough, ["welcome", "and", "thank", "you"])
    }

    func testCommandIsRecognisedAndItsWordsSwallowed() {
        let result = detector.process(["scroll", "up"])
        XCTAssertEqual(result.commands, [.back])
        // The critical part: if these reached the matcher they would drag the
        // cursor forward, undoing the jump the command just made.
        XCTAssertTrue(result.passthrough.isEmpty)
    }

    func testCommandSplitAcrossTwoCallbacks() {
        // Recognition delivers words in whatever chunks it likes.
        let first = detector.process(["scroll"])
        XCTAssertTrue(first.commands.isEmpty)
        XCTAssertTrue(first.passthrough.isEmpty, "an opening word is held, not emitted")

        let second = detector.process(["up"])
        XCTAssertEqual(second.commands, [.back])
        XCTAssertTrue(second.passthrough.isEmpty)
    }

    func testHeldWordIsReleasedWhenTheCommandDoesNotComplete() {
        _ = detector.process(["scroll"])
        let result = detector.process(["through", "the", "list"])
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.passthrough, ["scroll", "through", "the", "list"],
                       "a held word must reach the matcher in its original order")
    }

    func testBothDirections() {
        XCTAssertEqual(detector.process(["scroll", "down"]).commands, [.forward])
        XCTAssertEqual(VoiceCommandDetector().process(["scroll", "up"]).commands, [.back])
        XCTAssertEqual(VoiceCommand.back.lineOffset, -1)
        XCTAssertEqual(VoiceCommand.forward.lineOffset, 1)
    }

    func testRepeatedCommandsInOneDelta() {
        // "Repeat to go further" has to work even when both land together.
        let result = detector.process(["scroll", "up", "scroll", "up"])
        XCTAssertEqual(result.commands, [.back, .back])
        XCTAssertTrue(result.passthrough.isEmpty)
    }

    func testCommandSurroundedBySpeech() {
        let result = detector.process(["sorry", "scroll", "up", "let", "me", "retry"])
        XCTAssertEqual(result.commands, [.back])
        XCTAssertEqual(result.passthrough, ["sorry", "let", "me", "retry"])
    }

    func testScriptWinsardWhenItActuallySaysThePhrase() {
        // A script about scrolling must be readable without steering itself.
        let result = detector.process(["scroll", "up"], scriptAhead: ["scroll", "up", "to", "begin"])
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.passthrough, ["scroll", "up"])
    }

    func testPunctuationAndCaseDoNotDefeatTheCommand() {
        let result = detector.process(["Scroll,", "Up!"])
        XCTAssertEqual(result.commands, [.back])
    }

    func testMisheardCommandsStillWork() {
        // Recognition of a short phrase is harder than of running speech, and
        // harder still in an accent — the reason exact matching failed on
        // device while the script itself matched fine.
        XCTAssertEqual(VoiceCommandDetector().process(["scrawl", "up"]).commands, [.back],
                       "a near-miss on the command word should still steer")
        XCTAssertEqual(VoiceCommandDetector().process(["scrolled", "up"]).commands, [.back])
        XCTAssertEqual(VoiceCommandDetector().process(["scroll", "back"]).commands, [.back])
        XCTAssertEqual(VoiceCommandDetector().process(["go", "back"]).commands, [.back])
    }

    func testOrdinaryWordsAreNotMistakenForCommands() {
        // The looseness must not turn normal speech into steering.
        for words in [["so", "on"], ["up", "front"], ["going", "up"], ["scroll"]] {
            let result = VoiceCommandDetector().process(words + ["afterwards"])
            XCTAssertTrue(result.commands.isEmpty, "\(words) should not be a command")
        }
    }

    func testShortWordsAreMatchedStrictly() {
        // "up" must not fuzzy-match "on", or every sentence would steer.
        XCTAssertTrue(VoiceCommandDetector.matches("up", "up"))
        XCTAssertFalse(VoiceCommandDetector.matches("on", "up"))
        XCTAssertFalse(VoiceCommandDetector.matches("out", "up"))
    }

    func testResetDropsAnyHeldWord() {
        _ = detector.process(["scroll"])
        detector.reset()
        let result = detector.process(["ahead"])
        XCTAssertEqual(result.passthrough, ["ahead"], "a half-command must not survive into the next take")
    }
}

final class CursorLineMovementTests: XCTestCase {

    private func state(_ text: String) -> TeleprompterState {
        let s = TeleprompterState()
        s.scriptText = text
        s.buildWords()
        return s
    }

    func testBackStepsToTheStartOfThePreviousLine() {
        let s = state("one two three\nfour five six\nseven eight nine")
        s.activeIndex = 7            // "eight", on the third line
        s.moveCursor(lines: -1)
        XCTAssertEqual(s.words[s.activeIndex].raw, "four")
    }

    func testRepeatingTheCommandGoesFurtherBack() {
        let s = state("one two three\nfour five six\nseven eight nine")
        s.activeIndex = 7
        s.moveCursor(lines: -1)
        s.moveCursor(lines: -1)
        XCTAssertEqual(s.words[s.activeIndex].raw, "one")
    }

    func testForwardStepsToTheNextLine() {
        let s = state("one two three\nfour five six\nseven eight nine")
        s.activeIndex = 1
        s.moveCursor(lines: 1)
        XCTAssertEqual(s.words[s.activeIndex].raw, "four")
    }

    func testBlankLinesAreSkipped() {
        // Blank lines are ad-lib space, not somewhere to land.
        let s = state("one two\n\n\nthree four")
        s.activeIndex = 2            // "three"
        s.moveCursor(lines: -1)
        XCTAssertEqual(s.words[s.activeIndex].raw, "one")
    }

    func testClampsAtBothEnds() {
        let s = state("one two\nthree four")
        s.activeIndex = 0
        s.moveCursor(lines: -1)
        XCTAssertEqual(s.activeIndex, 0, "cannot go back past the start")

        s.activeIndex = 3
        s.moveCursor(lines: 1)
        XCTAssertEqual(s.words[s.activeIndex].raw, "three", "cannot go past the last line")
    }

    func testMovingBackMakesTheTextUnreadAgain() {
        // The cursor drives the colours, so stepping back is also what
        // "resets" already-spoken text.
        let s = state("one two three\nfour five six")
        s.activeIndex = 4
        XCTAssertEqual(s.state(for: 1), .spoken)
        s.moveCursor(lines: -1)
        XCTAssertEqual(s.state(for: 1), .upcoming)
    }

    func testUpcomingWordsReportsWhatIsAtTheCursor() {
        let s = state("scroll up to begin the talk")
        s.activeIndex = 0
        XCTAssertEqual(s.upcomingWords(3), ["scroll", "up", "to"])
        s.activeIndex = 4
        XCTAssertEqual(s.upcomingWords(4), ["the", "talk"], "must not run off the end")
    }

    func testMovementOnAnEmptyScriptIsHarmless() {
        let s = state("")
        s.moveCursor(lines: -1)
        XCTAssertEqual(s.activeIndex, 0)
        XCTAssertEqual(s.upcomingWords(3), [])
    }
}

final class ReadTextFadeTests: XCTestCase {

    func testTextJustReadStaysBright() {
        XCTAssertEqual(ReadTextFade.brightness(wordsBehind: 0, floor: 0.55),
                       ReadTextFade.nearBrightness, accuracy: 0.001)
    }

    func testBrightnessFallsWithDistanceAndNeverRises() {
        let values = (0...20).map { ReadTextFade.brightness(wordsBehind: $0, floor: 0.4) }
        XCTAssertEqual(values, values.sorted(by: >), "read text must only ever get dimmer")
        XCTAssertGreaterThan(values.first!, values.last!, "and must actually fade")
    }

    func testItSettlesAtTheChosenFloor() {
        XCTAssertEqual(ReadTextFade.brightness(wordsBehind: 40, floor: 0.4), 0.4, accuracy: 0.001)
        XCTAssertEqual(ReadTextFade.brightness(wordsBehind: 15, floor: 0.4), 0.4, accuracy: 0.001)
    }

    func testTheFloorIsHonouredAcrossItsRange() {
        for floor in [0.25, 0.4, 0.55, 0.7, 0.9] {
            let far = ReadTextFade.brightness(wordsBehind: 100, floor: floor)
            XCTAssertEqual(far, floor, accuracy: 0.001,
                           "distant text should settle at exactly the chosen floor")
        }
    }

    func testAFloorBrighterThanTheNearValueGivesFlatBrightness() {
        // Asking for read text brighter than the just-read value means "don't
        // fade at all" — it must not invert into text that brightens with age.
        let near = ReadTextFade.brightness(wordsBehind: 0, floor: 0.9)
        let far = ReadTextFade.brightness(wordsBehind: 30, floor: 0.9)
        XCTAssertEqual(near, far, accuracy: 0.001)
        XCTAssertEqual(far, 0.9, accuracy: 0.001)
    }

    func testOutOfRangeInputsAreClamped() {
        XCTAssertEqual(ReadTextFade.brightness(wordsBehind: -5, floor: 0.55),
                       ReadTextFade.nearBrightness, accuracy: 0.001)
        let tooDim = ReadTextFade.brightness(wordsBehind: 3, floor: -1)
        XCTAssertGreaterThanOrEqual(tooDim, ReadTextFade.floorRange.lowerBound)
    }

    func testAFloorBrighterThanTheNearValueDoesNotInvertTheFade() {
        // Guard against fading *upward* if the range ever changes.
        let value = ReadTextFade.brightness(wordsBehind: 5, floor: 0.9)
        XCTAssertLessThanOrEqual(value, 0.9)
        XCTAssertGreaterThan(value, 0)
    }

    func testTheDefaultFloorIsInsideTheOfferedRange() {
        XCTAssertTrue(ReadTextFade.floorRange.contains(ReadTextFade.defaultFloor))
    }
}

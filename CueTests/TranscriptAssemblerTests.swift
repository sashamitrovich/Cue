import XCTest
@testable import Cue

/// The iOS 26 analyzer reports stretches of audio, not the whole transcript
/// (#25). These pin that the assembler plus `TranscriptDeltaTracker` hand the
/// matcher each heard word exactly once, as the classic engine does.
final class TranscriptAssemblerTests: XCTestCase {
    private var assembler = TranscriptAssembler()
    private var delta = TranscriptDeltaTracker()

    private func feed(_ text: String, final: Bool = false) -> [String] {
        delta.newWords(in: assembler.apply(text, isFinal: final))
    }

    func testVolatileGuessesGrowWordByWord() {
        XCTAssertEqual(feed("Good"), ["Good"])
        XCTAssertEqual(feed("Good morning"), ["morning"])
        XCTAssertEqual(feed("Good morning everyone"), ["everyone"])
    }

    func testFinalizingTheSameWordsReplaysNothing() {
        _ = feed("Good morning")
        XCTAssertEqual(feed("Good morning", final: true), [])
    }

    func testTheNextStretchFollowsTheFinalizedOne() {
        // After a final result the next volatile result covers only new
        // audio; it must come out as new words, not a repeat.
        _ = feed("Good morning")
        _ = feed("Good morning", final: true)
        XCTAssertEqual(feed("and"), ["and"])
        XCTAssertEqual(feed("and welcome"), ["welcome"])
    }

    func testAShorterRevisionReplaysNothing() {
        // The analyzer changed its mind and the guess got shorter: re-sync,
        // never re-send the words the matcher already has.
        _ = feed("Good morning every one")
        XCTAssertEqual(feed("Good morning everyone"), [])
        XCTAssertEqual(feed("Good morning everyone and"), ["and"])
    }

    func testFinalLongerThanTheGuessSendsTheRest() {
        _ = feed("Thank")
        XCTAssertEqual(feed("Thank you all", final: true), ["you", "all"])
    }

    func testAnyWhitespaceSplitsWords() {
        XCTAssertEqual(feed(" Bom  dia\ta todos "), ["Bom", "dia", "a", "todos"])
    }

    func testResetStartsAnEmptyTranscript() {
        _ = feed("Good morning", final: true)
        assembler.reset()
        delta.reset()
        XCTAssertEqual(feed("Hello"), ["Hello"])
    }
}

/// The language picker's order (#25): on-device languages first, then server.
final class LanguageGroupingTests: XCTestCase {
    func testOnDeviceLanguagesComeFirstAndKeepTheirOrder() {
        let locales = ["ca-ES", "cs-CZ", "de-DE", "en-US", "it-IT"].map(Locale.init(identifier:))
        let groups = SpeechLocales.grouped(locales, local: ["it_IT", "de-DE", "en_US"])
        XCTAssertEqual(groups.onDevice.map(\.identifier), ["de-DE", "en-US", "it-IT"])
        XCTAssertEqual(groups.server.map(\.identifier), ["ca-ES", "cs-CZ"])
    }

    func testNothingKnownLocalPutsEverythingUnderServer() {
        let locales = ["ca-ES", "cs-CZ"].map(Locale.init(identifier:))
        let groups = SpeechLocales.grouped(locales, local: [])
        XCTAssertTrue(groups.onDevice.isEmpty)
        XCTAssertEqual(groups.server.count, 2)
    }
}

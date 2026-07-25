import XCTest
@testable import Cue

final class TranscriptDeltaTrackerTests: XCTestCase {

    func testFirstCallReturnsEverything() {
        var tracker = TranscriptDeltaTracker()
        XCTAssertEqual(tracker.newWords(in: ["hello", "there"]), ["hello", "there"])
    }

    func testOnlyAppendedWordsAreReturned() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: ["welcome", "and"])
        XCTAssertEqual(tracker.newWords(in: ["welcome", "and", "thank", "you"]), ["thank", "you"])
    }

    func testUnchangedTranscriptYieldsNothing() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: ["welcome", "and"])
        XCTAssertEqual(tracker.newWords(in: ["welcome", "and"]), [])
    }

    /// The recognizer refining its last word (e.g. "wel" -> "welcome") keeps the
    /// word count the same, so nothing should be replayed to the matcher.
    func testRevisedTailOfSameLengthYieldsNothing() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: ["welcome", "an"])
        XCTAssertEqual(tracker.newWords(in: ["welcome", "and"]), [])
    }

    func testShrinkingTranscriptResyncsWithoutReplaying() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: ["one", "two", "three", "four"])
        XCTAssertEqual(tracker.newWords(in: ["one", "two"]), [])
        // Subsequent growth resumes from the corrected position.
        XCTAssertEqual(tracker.newWords(in: ["one", "two", "five"]), ["five"])
    }

    func testResetReplaysFromTheStart() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: ["one", "two"])
        tracker.reset()
        XCTAssertEqual(tracker.newWords(in: ["three", "four"]), ["three", "four"])
    }

    func testEmptyTranscriptIsSafe() {
        var tracker = TranscriptDeltaTracker()
        XCTAssertEqual(tracker.newWords(in: []), [])
    }

    /// A whole spoken sentence arriving one partial at a time must hand each
    /// word to the matcher exactly once.
    func testIncrementalTranscriptEmitsEachWordExactlyOnce() {
        var tracker = TranscriptDeltaTracker()
        let sentence = ["the", "words", "you", "rehearse", "are", "never", "the", "words"]
        var emitted: [String] = []
        for count in 1...sentence.count {
            emitted += tracker.newWords(in: Array(sentence.prefix(count)))
        }
        XCTAssertEqual(emitted, sentence)
    }
}

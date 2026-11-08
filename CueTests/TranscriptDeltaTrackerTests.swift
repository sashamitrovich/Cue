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

    // MARK: transcript resets (#29)

    private let longTranscript = ["so", "the", "garden", "gate", "is", "wide", "the", "path", "stays", "the", "same", "today"]

    /// The classic recogniser restarts its running transcript at a pause: it
    /// drops from a dozen words to one or two without saying so. Those words
    /// are new speech and must reach the matcher.
    func testCollapsedTranscriptIsAResetWhenTheEngineCanReset() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: longTranscript, detectsReset: true)
        XCTAssertEqual(tracker.newWords(in: ["take"], detectsReset: true), ["take"],
                       "The first word after a reset was being thrown away")
        // ...and it carries on from there as normal.
        XCTAssertEqual(tracker.newWords(in: ["take", "1.2"], detectsReset: true), ["1.2"])
    }

    /// A recogniser merging words ("one point two" becoming "1.2") shortens the
    /// transcript a little. That is a correction of words already handed over,
    /// not new speech, and replaying it would push the cursor forward again.
    func testSmallShrinkIsStillARevisionNotAReset() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: longTranscript, detectsReset: true)
        let merged = Array(longTranscript.dropLast(2)) + ["1.2"]  // 11 words, from 12
        XCTAssertEqual(tracker.newWords(in: merged, detectsReset: true), [])
    }

    /// The iOS 26 analyzer path rebuilds a cumulative transcript itself and
    /// never resets; a shorter guess there is always a revision.
    func testResetIsNotDetectedUnlessTheEngineAsksForIt() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: longTranscript)
        XCTAssertEqual(tracker.newWords(in: ["take"]), [])
    }

    /// Early in a take a shrink from three words to one is ordinary revision;
    /// replaying it would feed back words the matcher has just used.
    func testShortTranscriptsAreNeverTreatedAsResets() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: ["seen", "one", "your"], detectsReset: true)
        XCTAssertEqual(tracker.newWords(in: ["scene"], detectsReset: true), [])
    }

    /// A revision that happens to halve the transcript but keeps its start is
    /// still a revision: the speaker did not begin a new utterance.
    func testHalvingRevisionThatKeepsTheFirstWordIsNotAReset() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: longTranscript, detectsReset: true)
        XCTAssertEqual(tracker.newWords(in: ["so", "the", "garden"], detectsReset: true), [])
    }

    /// Punctuation and case in the first word must not turn a revision into a
    /// reset ("So," against "so").
    func testFirstWordComparisonIgnoresPunctuationAndCase() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: ["So,"] + longTranscript.dropFirst(), detectsReset: true)
        XCTAssertEqual(tracker.newWords(in: ["so", "the", "garden"], detectsReset: true), [])
    }

    /// Known gap, documented in AGENTS.md: a reset that starts with the same
    /// word as the transcript before it looks like a revision, so its words
    /// are lost. Remove the wrapper if the tracker ever learns to tell them
    /// apart.
    func testResetStartingWithTheSameWordIsAKnownGap() {
        var tracker = TranscriptDeltaTracker()
        _ = tracker.newWords(in: longTranscript, detectsReset: true)
        XCTExpectFailure("A reset beginning with the previous first word is taken for a revision") {
            XCTAssertEqual(tracker.newWords(in: ["so"], detectsReset: true), ["so"])
        }
    }
}

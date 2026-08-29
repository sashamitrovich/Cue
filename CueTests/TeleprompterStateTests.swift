import XCTest
@testable import Cue

final class TeleprompterStateTests: XCTestCase {

    // MARK: - normalize(_:)

    func testNormalizeLowercases() {
        XCTAssertEqual(TeleprompterState.normalize("HELLO"), "hello")
    }

    func testNormalizeStripsPunctuationButKeepsApostrophe() {
        XCTAssertEqual(TeleprompterState.normalize("don't"), "don't")
        XCTAssertEqual(TeleprompterState.normalize("Hello,"), "hello")
        XCTAssertEqual(TeleprompterState.normalize("Wait!!"), "wait")
        XCTAssertEqual(TeleprompterState.normalize("\"quoted\""), "quoted")
    }

    func testNormalizeKeepsNumbers() {
        XCTAssertEqual(TeleprompterState.normalize("Room101."), "room101")
    }

    func testNormalizeEmptyString() {
        XCTAssertEqual(TeleprompterState.normalize(""), "")
    }

    func testNormalizeOnlyPunctuation() {
        XCTAssertEqual(TeleprompterState.normalize("---!!!"), "")
    }

    // MARK: - buildWords()

    func testBuildWordsTokenizesAndResetsCursor() {
        let state = TeleprompterState()
        state.scriptText = "Hello there, world!"
        state.activeIndex = 5 // simulate progress before rebuilding
        state.buildWords()

        XCTAssertEqual(state.words.count, 3)
        XCTAssertEqual(state.words.map(\.raw), ["Hello", "there,", "world!"])
        XCTAssertEqual(state.words.map(\.norm), ["hello", "there", "world"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    func testBuildWordsAcrossMultipleParagraphs() {
        let state = TeleprompterState()
        state.scriptText = """
        First paragraph line one. Second line here.

        Second paragraph starts now. It has more words too.
        """
        state.buildWords()

        // buildWords only splits on whitespace, so blank lines don't add words.
        let expectedWordCount = state.scriptText.split(whereSeparator: { $0.isWhitespace }).count
        XCTAssertEqual(state.words.count, expectedWordCount)
        XCTAssertEqual(state.words.first?.raw, "First")
        XCTAssertEqual(state.words.last?.raw, "too.")
        XCTAssertEqual(state.activeIndex, 0)

        // ids should be sequential starting at 0
        XCTAssertEqual(state.words.map(\.id), Array(0..<state.words.count))
    }

    func testBuildWordsWithDefaultScriptIsNonEmpty() {
        let state = TeleprompterState()
        state.buildWords()
        XCTAssertFalse(state.words.isEmpty)
        XCTAssertEqual(state.activeIndex, 0)
    }

    // MARK: - ingest(transcriptWords:) — helpers

    private func makeState(_ script: String) -> TeleprompterState {
        let state = TeleprompterState()
        state.scriptText = script
        state.buildWords()
        return state
    }

    // MARK: - ingest — exact sequential matches

    func testIngestExactSequentialMatchAdvancesCursor() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["the", "quick", "brown"])
        XCTAssertEqual(state.activeIndex, 3) // positioned right after "brown"
    }

    func testIngestSingleWordAdvancesByOne() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["the"])
        XCTAssertEqual(state.activeIndex, 1)
    }

    // MARK: - ingest — skipping across the window when words are dropped/misheard

    func testIngestSkipsForwardWhenWordsAreMissed() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        // "fox" is several words into the window from activeIndex 0; matcher
        // should skip past the unheard "quick brown" and land after "fox".
        state.ingest(transcriptWords: ["fox"])
        XCTAssertEqual(state.activeIndex, 4) // index of "fox" is 3, cursor -> 4
    }

    func testIngestSkipsWithinWindowLimit() {
        // WINDOW is 12; from activeIndex 0 the reachable indices are 0...11.
        // Put "target" at index 11 (11 filler words before it) so it's the
        // last word still inside the window.
        let words = (0..<11).map { "word\($0)" }.joined(separator: " ") + " target"
        let state = makeState(words)
        state.ingest(transcriptWords: ["target"])
        XCTAssertEqual(state.activeIndex, 11) // "target" is at index 11, cursor -> 12, clamped to count-1
    }

    func testIngestDoesNotMatchBeyondWindow() {
        // Put "target" at index 12, one past the last index (11) reachable
        // from activeIndex 0 with WINDOW=12.
        let words = (0..<12).map { "word\($0)" }.joined(separator: " ") + " target"
        let state = makeState(words)
        state.ingest(transcriptWords: ["target"])
        // "target" sits outside limit = min(count, 0+12) = 12 (loop covers j < 12,
        // i.e. indices 0...11), so it should not be found and the cursor stays put.
        XCTAssertEqual(state.activeIndex, 0)
    }

    // MARK: - ingest — adaptive search radius (ad-libbing and skipped passages)
    //
    // The reader going off-script is the normal case for this app, not an
    // edge case: paraphrasing, skipping a sentence, or simply being misheard
    // all look identical from the matcher's side — words arrive and none of
    // them are in the window. With a fixed window the cursor stops there and
    // waits forever for words that will never be said, and the script sits
    // still while the reader keeps talking.

    /// Script long enough for a skip to land well outside the ordinary
    /// 12-word window, with distinctive landmark words to re-anchor on.
    private func makeLongScript() -> TeleprompterState {
        let filler = (0..<30).map { "padding\($0)" }.joined(separator: " ")
        return makeState("opening line here \(filler) landmark continues afterwards")
    }

    func testAFixedWindowWouldStrandTheCursorButTheSearchWidens() {
        let state = makeLongScript()
        // "landmark" sits ~33 words ahead — far outside the ordinary window.
        // The first attempts find nothing, which is what widens the search.
        for _ in 0..<5 {
            state.ingest(transcriptWords: ["improvised"])
        }
        XCTAssertEqual(state.activeIndex, 0, "unmatched words must not move the cursor")

        state.ingest(transcriptWords: ["landmark"])
        XCTAssertGreaterThan(
            state.activeIndex, 30,
            "after sustained non-matching speech the matcher must re-anchor "
            + "on a landmark word instead of waiting forever"
        )
    }

    func testTheWindowStaysNarrowWhileReadingIsGoingWell() {
        let state = makeLongScript()
        // No misses yet, so a far-off word must not be reachable — otherwise
        // every common word becomes a chance to run away from the reader.
        state.ingest(transcriptWords: ["landmark"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    func testAMatchResetsTheWidening() {
        let state = makeLongScript()
        for _ in 0..<5 { state.ingest(transcriptWords: ["improvised"]) }
        // Reading resumes normally from the top of the script...
        state.ingest(transcriptWords: ["opening"])
        XCTAssertEqual(state.activeIndex, 1)
        // ...so the search must be narrow again, and the distant landmark
        // out of reach.
        state.ingest(transcriptWords: ["landmark"])
        XCTAssertEqual(state.activeIndex, 1, "a successful match must re-narrow the search")
    }

    func testAShortWordCannotAnchorALongJump() {
        let filler = (0..<30).map { "padding\($0)" }.joined(separator: " ")
        let state = makeState("opening line here \(filler) cat continues afterwards")
        for _ in 0..<5 { state.ingest(transcriptWords: ["improvised"]) }
        // "cat" is distinctive in this script but only three letters. A long
        // jump on a short word is how a prompter runs away from its reader.
        state.ingest(transcriptWords: ["cat"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    func testFillerStillCannotAnchorALongJumpEvenWhenLost() {
        let filler = (0..<30).map { "padding\($0)" }.joined(separator: " ")
        let state = makeState("opening line here \(filler) their continues afterwards")
        for _ in 0..<5 { state.ingest(transcriptWords: ["improvised"]) }
        // "their" is five letters, so it clears the length guard — but it is
        // filler, and filler may never match beyond `fillerReach`.
        state.ingest(transcriptWords: ["their"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    func testResyncMatcherNarrowsTheSearchAgain() {
        let state = makeLongScript()
        for _ in 0..<5 { state.ingest(transcriptWords: ["improvised"]) }
        // Standing in for a restart, a drag or a voice command: the reader
        // has just said where they are, so the matcher is no longer lost.
        state.resyncMatcher()
        state.ingest(transcriptWords: ["landmark"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    // MARK: - ingest — prefix matching

    func testIngestPrefixMatchHeardWordIsPrefixOfScriptWord() {
        let state = makeState("welcome everyone to the presentation today")
        // "present" (7 chars, >3) is a prefix of script word "presentation".
        state.ingest(transcriptWords: ["welcome", "everyone", "to", "the", "present"])
        XCTAssertEqual(state.activeIndex, 5) // matched through "presentation"
    }

    func testIngestPrefixMatchScriptWordIsPrefixOfHeardWord() {
        let state = makeState("welcome everyone to the present moment")
        // script word "present" (7 chars, >3) is a prefix of heard "presentation".
        state.ingest(transcriptWords: ["welcome", "everyone", "to", "the", "presentation"])
        XCTAssertEqual(state.activeIndex, 5)
    }

    func testIngestPrefixMatchRequiresMoreThanThreeChars() {
        // Both words are <=3 chars ("cat" vs "cats" -> "cat" has 3 chars so
        // the >3 requirement on the heard word fails using "cat"; script word
        // "cats" has 4 chars so nw.hasPrefix(word) could apply, but only when
        // nw.count > 3 -- verify the exact-match fallback still works for
        // short words, and that a genuine short mismatch does not match.
        let state = makeState("a cat sat on a mat")
        state.ingest(transcriptWords: ["cat"])
        XCTAssertEqual(state.activeIndex, 2) // exact match at index 1
    }

    func testIngestShortWordMismatchDoesNotMatch() {
        // "ca" (2 chars) should not prefix-match "cat" (3 chars, not >3) since
        // neither the heard word nor script word exceeds the 3-char threshold
        // in a way that satisfies the prefix rule for both directions here.
        let state = makeState("a cat sat on a mat")
        state.ingest(transcriptWords: ["ca"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    // MARK: - ingest — no match within window

    func testIngestUnmatchedWordDoesNotMoveCursor() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["zebra"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    func testIngestMixOfMatchedAndUnmatchedWords() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["the", "quick", "zebra", "fox"])
        // "the"->1, "quick"->2, "zebra" no match (limit stays from cursor=2),
        // "fox" found at index 3 -> cursor 4.
        XCTAssertEqual(state.activeIndex, 4)
    }

    // MARK: - ingest — cursor never regresses

    func testIngestCursorNeverRegresses() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["the", "quick", "brown", "fox"])
        let advancedIndex = state.activeIndex
        XCTAssertGreaterThan(advancedIndex, 0)

        // Now feed words that only match earlier in the script (before cursor);
        // since matching only searches forward from the cursor, this should not
        // move activeIndex backward.
        state.ingest(transcriptWords: ["the", "quick"])
        XCTAssertGreaterThanOrEqual(state.activeIndex, advancedIndex)
    }

    func testIngestNoAdvanceLeavesIndexUnchanged() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["the", "quick"])
        let idx = state.activeIndex
        state.ingest(transcriptWords: ["gibberish", "nonsense"])
        XCTAssertEqual(state.activeIndex, idx)
    }

    // MARK: - ingest — clamping to last word index

    func testIngestClampsToLastWordIndex() {
        let state = makeState("one two three")
        state.ingest(transcriptWords: ["one", "two", "three"])
        // cursor would be 3 (words.count), but should clamp to count - 1 = 2.
        XCTAssertEqual(state.activeIndex, state.words.count - 1)
        XCTAssertEqual(state.activeIndex, 2)
    }

    func testIngestClampsWhenOverrunningWithExtraWords() {
        let state = makeState("one two three")
        state.ingest(transcriptWords: ["one", "two", "three", "four", "five"])
        XCTAssertEqual(state.activeIndex, state.words.count - 1)
    }

    // MARK: - ingest — empty/whitespace transcripts are no-ops

    func testIngestEmptyArrayIsNoOp() {
        let state = makeState("the quick brown fox")
        state.ingest(transcriptWords: [])
        XCTAssertEqual(state.activeIndex, 0)
    }

    func testIngestWhitespaceOnlyWordsAreNoOp() {
        let state = makeState("the quick brown fox")
        state.ingest(transcriptWords: ["   ", "", "\n"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    func testIngestOnEmptyScriptIsNoOp() {
        let state = TeleprompterState()
        state.words = []
        state.activeIndex = 0
        state.ingest(transcriptWords: ["hello", "world"])
        XCTAssertEqual(state.activeIndex, 0)
    }

    // MARK: - ingest — case-insensitivity and punctuation defensiveness

    func testIngestIsCaseInsensitive() {
        let state = makeState("Welcome Everyone Today")
        state.ingest(transcriptWords: ["WELCOME", "EVERYONE"])
        XCTAssertEqual(state.activeIndex, 2)
    }

    func testIngestIgnoresPunctuationInHeardWords() {
        let state = makeState("welcome everyone today")
        state.ingest(transcriptWords: ["welcome,", "everyone!"])
        XCTAssertEqual(state.activeIndex, 2)
    }

    func testIngestHandlesApostrophesInHeardWords() {
        let state = makeState("don't stop believing now")
        state.ingest(transcriptWords: ["don't", "stop"])
        XCTAssertEqual(state.activeIndex, 2)
    }

    // MARK: - state(for:)

    func testStateForClassifiesSpokenActiveUpcoming() {
        let state = makeState("one two three four five")
        state.activeIndex = 2

        XCTAssertEqual(state.state(for: 0), .spoken)
        XCTAssertEqual(state.state(for: 1), .spoken)
        XCTAssertEqual(state.state(for: 2), .active)
        XCTAssertEqual(state.state(for: 3), .upcoming)
        XCTAssertEqual(state.state(for: 4), .upcoming)
    }

    func testStateForAtZeroIndex() {
        let state = makeState("one two three")
        XCTAssertEqual(state.state(for: 0), .active)
        XCTAssertEqual(state.state(for: 1), .upcoming)
    }

    // MARK: - integration: ingest driving state(for:) end to end

    func testIngestThenStateForReflectsProgress() {
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["the", "quick", "brown"])

        XCTAssertEqual(state.state(for: 0), .spoken)
        XCTAssertEqual(state.state(for: 1), .spoken)
        XCTAssertEqual(state.state(for: 2), .spoken)
        XCTAssertEqual(state.state(for: 3), .active)
        XCTAssertEqual(state.state(for: 4), .upcoming)
    }
}

import XCTest
@testable import Cue

/// Pressure tests for the matcher's runaway guards — the behaviour behind the
/// prompter "jumping" or "stalling" during real speech. "Common" is derived
/// from the script's own word frequency (`commonWordMinOccurrences`, currently
/// 3), not a hand-written English list, and a far re-anchor also requires a word
/// long enough to be a trustworthy landmark (`minimumAnchorLength`).
///
/// These aim at real reader behaviour — paraphrasing, skipping, refrains,
/// repeated long words — not just at confirming a guard fires.
final class FillerWordJumpTests: XCTestCase {

    private func makeState(_ script: String) -> TeleprompterState {
        let state = TeleprompterState()
        state.scriptText = script
        state.buildWords()
        return state
    }

    /// Feed words that are not in the script to drive the matcher into its
    /// widened search state (`missesBeforeWidening`), the way a stretch of
    /// ad-libbing does. Must be a separate ingest — `unmatchedWords` only
    /// updates between calls.
    private func loseTheReader(_ state: TeleprompterState) {
        state.ingest(transcriptWords: ["zzxq", "qqwz", "wxzq", "zqwx", "xwzq"])
    }

    // MARK: frequency vs. length — the #13 mechanism, isolated

    /// The same long word ("presentation", 12 letters — well over the old
    /// `minimumAnchorLength` of 4) decides a far jump purely on how often it
    /// recurs. Recurring three times, it is an unreliable landmark and must NOT
    /// anchor a far jump. The old length-only rule would have allowed this — this
    /// is the case #13 exists to fix.
    func testLongRecurringWordIsGuardedWhereLengthAloneWouldNot() {
        let script = "presentation aa bb cc dd ee ff gg hh ii jj kk ll mm nn presentation oo presentation"
        // presentation at idx 0, 15, 17 → common (3x)
        let state = makeState(script)
        state.activeIndex = 1
        loseTheReader(state)
        state.ingest(transcriptWords: ["presentation"])
        XCTAssertEqual(state.activeIndex, 1,
            "A long word that recurs in the script must not anchor a far jump, even though it is long")
    }

    /// Same word, same length, same far distance — but occurring only twice it
    /// IS a reliable landmark, so it should re-anchor after a deviation. This is
    /// the recovery path, and pins that frequency (not length) is what changed.
    func testLongRareWordStillReAnchorsFarJump() {
        let script = "presentation aa bb cc dd ee ff gg hh ii jj kk ll mm nn presentation"
        // presentation at idx 0, 15 → rare (2x)
        let state = makeState(script)
        state.activeIndex = 1
        loseTheReader(state)
        state.ingest(transcriptWords: ["presentation"])
        XCTAssertEqual(state.activeIndex, 15,
            "A long word occurring only twice should re-anchor a far jump after a deviation")
    }

    // MARK: common words do not leap ahead

    func testCommonWordDoesNotJumpAcrossTheWindow() {
        // "the" recurs (idx 0,4,8,12) so it is common. From a cursor at idx 1,
        // hearing "the" must not leap to the distant one.
        let state = makeState("the sun rose and the birds sang while the town woke to the day")
        state.activeIndex = 1
        state.ingest(transcriptWords: ["the"])
        XCTAssertEqual(state.activeIndex, 1, "A common word should not skip ahead to a later occurrence")
    }

    func testCommonWordStillMatchesAtCursor() {
        let state = makeState("the the the sun rose over hills")
        state.ingest(transcriptWords: ["the"])
        XCTAssertEqual(state.activeIndex, 1, "A common word at the cursor must still advance normally")
    }

    func testCommonWordMatchesOneWordAhead() {
        // "it" recurs (idx 1,3,5); heard one position ahead of the cursor it must
        // still match (the dropped-word case).
        let state = makeState("run it run it run it now")
        state.ingest(transcriptWords: ["it"])
        XCTAssertEqual(state.activeIndex, 2, "A common word one position ahead should still match")
    }

    /// The short word that recurs only twice: not "common" by frequency, but
    /// anchoring a far jump on "so" is exactly the ad-lib runaway — and "so"
    /// recurs precisely when the reader is ad-libbing. The length floor must
    /// still block it, since frequency alone would not.
    func testShortWordAppearingTwiceDoesNotAnchorFarJump() {
        let state = makeState("alpha bravo charlie delta echo so foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo so")
        // "so" at idx 5, 19
        state.activeIndex = 6
        loseTheReader(state)
        state.ingest(transcriptWords: ["so"])
        XCTAssertEqual(state.activeIndex, 6, "A short word occurring twice must not anchor a far jump, even when rare")
    }

    // MARK: language-agnostic — the point of deriving from frequency

    func testCommonWordGuardWorksInAnyLanguage() {
        // Serbian (latinica): "se" recurs (idx 1,5,8). A static English filler
        // list would not guard it — the non-English lurching bug. It must not
        // leap from a cursor at idx 2 to the later "se".
        let state = makeState("vrata se otvaraju i deca se smeju dok se raduju")
        state.activeIndex = 2
        state.ingest(transcriptWords: ["se"])
        XCTAssertEqual(state.activeIndex, 2, "A word common in this script must be guarded regardless of language")
    }

    func testForeignFunctionWordAppearingOnceIsGuarded() {
        // "koji" (Croatian, 4 letters so it clears the length floor) appears
        // once, so frequency does not guard it — only the per-language list can.
        // Isolates that the list works for a non-English recognition locale.
        let padding = (0..<30).map { "rec\($0)" }.joined(separator: " ")
        let state = makeState("pocetak ovdje sada \(padding) koji nastavlja dalje")
        state.recognitionLocale = "hr-HR"
        for _ in 0..<5 { state.ingest(transcriptWords: ["improvizirano"]) }
        state.ingest(transcriptWords: ["koji"])
        XCTAssertEqual(state.activeIndex, 0,
            "A once-occurring function word of the recognition language must be guarded, in any language")
    }

    // MARK: real ad-lib behaviour

    /// Paraphrase: read two words, ad-lib three that are not in the script, then
    /// rejoin on a script word still inside the window. The cursor should follow
    /// to the rejoin point, not stall and not race.
    func testParaphraseThenRejoinWithinWindowKeepsTracking() {
        let state = makeState("our results this quarter exceeded every forecast the team set new records")
        state.ingest(transcriptWords: ["our"])
        state.ingest(transcriptWords: ["results"])
        for filler in ["were", "truly", "amazing"] {  // paraphrase, off script
            state.ingest(transcriptWords: [filler])
        }
        state.ingest(transcriptWords: ["forecast"])  // idx 6, back on script
        XCTAssertEqual(state.activeIndex, 7, "After a short paraphrase the cursor should rejoin on the next spoken script word")
    }

    /// A longer deviation crosses `missesBeforeWidening`, so the rejoin word sits
    /// beyond the ordinary window. The widened search must find it and re-anchor.
    func testLongAdLibThenRejoinBeyondWindow() {
        let state = makeState("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango")
        state.ingest(transcriptWords: ["alpha"])
        state.ingest(transcriptWords: ["bravo"])
        loseTheReader(state)  // 5 off-script words -> widened
        state.ingest(transcriptWords: ["sierra"])  // idx 18, past the window
        XCTAssertEqual(state.activeIndex, 19, "A widened search should re-anchor on a distinctive word past the window")
    }

    /// A refrain repeated verbatim (like a real speech) must track sequentially
    /// through each repetition rather than jumping to a later identical line.
    func testRepeatedRefrainTracksSequentially() {
        let state = makeState("i have a dream today i have a dream tomorrow i have a dream always")
        // Read the whole first refrain and into the second.
        for word in ["i", "have", "a", "dream", "today", "i", "have", "a", "dream"] {
            state.ingest(transcriptWords: [word])
        }
        // Cursor should sit just after the SECOND "dream" (idx 8), not the third.
        XCTAssertEqual(state.activeIndex, 9, "A repeated refrain must advance one repetition at a time, not leap to a later one")
    }

    func testRepetitiveScriptTracksSequentially() {
        let script = "know where it starts know where it turns and know exactly how it ends"
        let state = makeState(script)
        for word in ["know", "where", "it", "starts"] {
            state.ingest(transcriptWords: [word])
        }
        XCTAssertEqual(state.activeIndex, 4, "Cursor should sit just after the first 'starts', not race ahead")
    }

    // MARK: distinctive words keep their reach; bounds

    func testDistinctiveWordMayStillSkipAheadInWindow() {
        let state = makeState("one two three four five jumps six seven")
        state.ingest(transcriptWords: ["jumps"])
        XCTAssertEqual(state.activeIndex, 6, "A distinctive word should still skip to its match")
    }

    /// KNOWN GAP: reader doubles back by voice to re-read an earlier line.
    /// Because the matcher only searches forward, and "the hero" recurs, the
    /// cursor leaps FORWARD to the later copy — the opposite of the reader's
    /// intent, against the README's "double back" promise. This is pre-existing
    /// (the old filler list blocked "the" but "hero" jumped just the same) and
    /// deliberate moves are meant to rewind via a drag (`resyncMatcher`), not
    /// voice. The assertion below states the behaviour we want; `XCTExpectFailure`
    /// records that it does not yet hold. Remove the wrapper when voice
    /// double-back is actually supported.
    func testDoublingBackByVoiceDoesNotLeapForward() {
        let state = makeState("chapter one begins the hero departs chapter two begins the hero returns")
        // idx: chapter0 one1 begins2 the3 hero4 departs5 chapter6 two7 begins8 the9 hero10 returns11
        state.activeIndex = 6  // reader is at "chapter two"
        state.ingest(transcriptWords: ["the"])   // doubling back to re-read "the hero"
        state.ingest(transcriptWords: ["hero"])
        XCTExpectFailure("Voice-only double-back is not yet supported; the forward-only matcher leaps to the later identical phrase (cursor 6 -> 11).")
        XCTAssertLessThanOrEqual(state.activeIndex, 6,
            "Doubling back by voice must not leap the cursor forward to a later identical phrase")
    }

    func testCursorAtEndOfScriptDoesNotOverrun() {
        let state = makeState("one two three")
        state.activeIndex = 2
        state.ingest(transcriptWords: ["three"])
        state.ingest(transcriptWords: ["four"])
        XCTAssertEqual(state.activeIndex, 2, "At the last word the cursor must clamp, not run off the end")
    }
}

import XCTest
@testable import Cue

/// Covers the guard that stops common words from skipping the cursor far
/// ahead — the behaviour behind the prompter "jumping" during real speech.
final class FillerWordJumpTests: XCTestCase {

    private func makeState(_ script: String) -> TeleprompterState {
        let state = TeleprompterState()
        state.scriptText = script
        state.buildWords()
        return state
    }

    func testFillerWordDoesNotJumpAcrossTheWindow() {
        // "the" appears at index 0 and again at index 9. From a cursor sitting
        // at index 1, hearing "the" must not leap to the distant one.
        let state = makeState("the quick brown fox jumps over a lazy sleepy the dog")
        state.activeIndex = 1
        state.ingest(transcriptWords: ["the"])
        XCTAssertEqual(state.activeIndex, 1, "A filler word should not skip ahead to a later occurrence")
    }

    func testFillerWordStillMatchesAtCursor() {
        let state = makeState("the quick brown fox")
        state.ingest(transcriptWords: ["the"])
        XCTAssertEqual(state.activeIndex, 1, "A filler word at the cursor must still advance normally")
    }

    func testFillerWordMatchesOneWordAhead() {
        // Normal case for a dropped word: script "and the", heard just "the".
        let state = makeState("and the quick brown fox")
        state.ingest(transcriptWords: ["the"])
        XCTAssertEqual(state.activeIndex, 2, "A filler word one position ahead should still match")
    }

    func testContentWordMayStillSkipAhead() {
        // Distinctive words are how the matcher recovers from missed words, so
        // they keep their full reach across the window.
        let state = makeState("the quick brown fox jumps over the lazy dog")
        state.ingest(transcriptWords: ["jumps"])
        XCTAssertEqual(state.activeIndex, 5, "A distinctive word should still skip to its match")
    }

    /// Reading a passage that repeats filler words heavily should track roughly
    /// in step rather than racing to the end.
    func testRepetitiveScriptTracksSequentially() {
        let script = "know where it starts know where it turns and know exactly how it ends"
        let state = makeState(script)
        for word in ["know", "where", "it", "starts"] {
            state.ingest(transcriptWords: [word])
        }
        XCTAssertEqual(state.activeIndex, 4, "Cursor should sit just after the first 'starts', not race ahead")
    }
}

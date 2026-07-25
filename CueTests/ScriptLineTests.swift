import XCTest
@testable import Cue

/// Covers line grouping — the prompter reproduces the editor's line breaks and
/// blank lines, while the flat word list the matcher uses stays unchanged.
final class ScriptLineTests: XCTestCase {

    private func makeState(_ script: String) -> TeleprompterState {
        let state = TeleprompterState()
        state.scriptText = script
        state.buildWords()
        return state
    }

    func testSingleLineProducesOneLine() {
        let state = makeState("hello there world")
        XCTAssertEqual(state.lines.count, 1)
        XCTAssertEqual(state.lines[0].words.map(\.raw), ["hello", "there", "world"])
        XCTAssertFalse(state.lines[0].isBlank)
    }

    func testBlankLineIsPreservedBetweenParagraphs() {
        let state = makeState("first para\n\nsecond para")
        XCTAssertEqual(state.lines.count, 3)
        XCTAssertFalse(state.lines[0].isBlank)
        XCTAssertTrue(state.lines[1].isBlank, "The blank line must survive as real space")
        XCTAssertFalse(state.lines[2].isBlank)
    }

    func testMultipleConsecutiveBlankLinesAreAllKept() {
        // Deliberate ad-lib room: three blank lines should not collapse into one.
        let state = makeState("intro\n\n\n\noutro")
        XCTAssertEqual(state.lines.filter(\.isBlank).count, 3)
    }

    func testTrailingBlankLinesAreTrimmed() {
        let state = makeState("only line\n\n\n")
        XCTAssertEqual(state.lines.count, 1, "Trailing blanks would only add dead space")
    }

    func testWordIdsStaySequentialAcrossLines() {
        let state = makeState("one two\n\nthree four\nfive")
        XCTAssertEqual(state.words.map(\.raw), ["one", "two", "three", "four", "five"])
        XCTAssertEqual(state.words.map(\.id), [0, 1, 2, 3, 4])
        // The ids inside the line groups must agree with the flat list.
        XCTAssertEqual(state.lines.flatMap { $0.words }.map(\.id), [0, 1, 2, 3, 4])
    }

    func testBlankLinesAddNoWords() {
        let state = makeState("a\n\n\nb")
        XCTAssertEqual(state.words.count, 2)
    }

    func testLineBreakWithoutBlankLineStillSplitsLines() {
        let state = makeState("line one\nline two")
        XCTAssertEqual(state.lines.count, 2)
        XCTAssertEqual(state.words.count, 4)
    }
}

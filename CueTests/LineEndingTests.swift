import XCTest
@testable import Cue

/// Imported files often carry Windows or classic-Mac line endings; those must
/// not turn into phantom blank lines in the prompter.
final class LineEndingTests: XCTestCase {

    private func makeState(_ script: String) -> TeleprompterState {
        let state = TeleprompterState()
        state.scriptText = script
        state.buildWords()
        return state
    }

    func testCRLFDoesNotCreatePhantomBlankLines() {
        let state = makeState("line one\r\nline two\r\nline three")
        XCTAssertEqual(state.lines.count, 3)
        XCTAssertFalse(state.lines.contains(where: \.isBlank))
    }

    func testCRLFBlankLineIsStillABlankLine() {
        let state = makeState("para one\r\n\r\npara two")
        XCTAssertEqual(state.lines.count, 3)
        XCTAssertTrue(state.lines[1].isBlank)
    }

    func testClassicMacCROnlyLineEndings() {
        let state = makeState("line one\rline two")
        XCTAssertEqual(state.lines.count, 2)
        XCTAssertFalse(state.lines.contains(where: \.isBlank))
    }

    func testWordCountUnaffectedByLineEndingStyle() {
        let lf = makeState("a b\nc d")
        let crlf = makeState("a b\r\nc d")
        XCTAssertEqual(lf.words.count, crlf.words.count)
        XCTAssertEqual(crlf.words.map(\.raw), ["a", "b", "c", "d"])
    }
}

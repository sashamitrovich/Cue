import XCTest
@testable import Cue

final class ScriptImporterTests: XCTestCase {

    func testReadsUTF8Text() {
        let data = Data("Hello — script with em dash and ünïcode".utf8)
        XCTAssertEqual(ScriptImporter.text(from: data, fileExtension: "txt"),
                       "Hello — script with em dash and ünïcode")
    }

    func testPreservesLineBreaksAndBlankLines() {
        let source = "First line\n\nSecond after blank\nThird"
        let data = Data(source.utf8)
        XCTAssertEqual(ScriptImporter.text(from: data, fileExtension: "txt"), source)
    }

    func testReadsMarkdownAsPlainText() {
        let data = Data("# Heading\n\nBody text".utf8)
        XCTAssertEqual(ScriptImporter.text(from: data, fileExtension: "md"), "# Heading\n\nBody text")
    }

    func testReadsUTF16WithBOM() {
        let source = "UTF sixteen script"
        var data = Data([0xFF, 0xFE]) // little-endian BOM
        data.append(source.data(using: .utf16LittleEndian)!)
        XCTAssertEqual(ScriptImporter.plainText(from: data), source)
    }

    func testStripsRTFFormattingToPlainText() {
        let rtf = #"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs28 Hello \b bold\b0  world}"#
        let data = Data(rtf.utf8)
        let text = ScriptImporter.text(from: data, fileExtension: "rtf")
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("Hello"), "RTF control words should be stripped, text kept")
        XCTAssertTrue(text!.contains("bold"))
        XCTAssertFalse(text!.contains("rtf1"), "Control words must not leak into the script")
    }

    func testEmptyDataYieldsEmptyString() {
        XCTAssertEqual(ScriptImporter.text(from: Data(), fileExtension: "txt"), "")
    }
}

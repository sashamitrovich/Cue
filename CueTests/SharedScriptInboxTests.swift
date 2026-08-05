import XCTest
@testable import Cue

final class SharedScriptInboxTests: XCTestCase {

    private var directory: URL!
    private var inbox: SharedScriptInbox!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inbox-\(UUID().uuidString)")
        inbox = SharedScriptInbox(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testNothingPendingWhenNothingWasShared() {
        XCTAssertNil(inbox.pending())
    }

    func testStoredScriptComesBack() throws {
        try inbox.store("Welcome, and thank you for being here.", named: "Keynote open")
        let pending = try XCTUnwrap(inbox.pending())
        XCTAssertEqual(pending.text, "Welcome, and thank you for being here.")
        XCTAssertEqual(pending.name, "Keynote open")
    }

    func testTheNewestShareWins() throws {
        try inbox.store("first", named: "one")
        // Filenames carry a millisecond stamp; make sure the two differ.
        Thread.sleep(forTimeInterval: 0.01)
        try inbox.store("second", named: "two")
        XCTAssertEqual(inbox.pending()?.text, "second")
    }

    func testTwoSharesInQuickSuccessionDoNotOverwriteEachOther() throws {
        let a = try inbox.store("first", named: "one")
        Thread.sleep(forTimeInterval: 0.01)
        let b = try inbox.store("second", named: "two")
        XCTAssertNotEqual(a, b, "each share needs its own file")
    }

    func testClearingRemovesThePendingScript() throws {
        try inbox.store("something", named: "note")
        inbox.clear()
        XCTAssertNil(inbox.pending(), "a script must not be offered twice")
    }

    func testBlankSharesAreIgnored() throws {
        try inbox.store("   \n  \n", named: "empty")
        XCTAssertNil(inbox.pending(), "whitespace is not a script")
    }

    func testAwkwardNamesDoNotBreakTheFilename() throws {
        try inbox.store("body", named: "Q3 / Board Update: \"final\"")
        let pending = try XCTUnwrap(inbox.pending())
        XCTAssertEqual(pending.text, "body")
        XCTAssertFalse(pending.name.isEmpty)
    }

    func testUnnamedSharesStillWork() throws {
        try inbox.store("body")
        XCTAssertEqual(inbox.pending()?.text, "body")
    }
}

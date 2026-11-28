import XCTest
@testable import Cue

/// The script itself survives a relaunch (#34). A reviewer pasted a script,
/// relaunched, and found the English sample back and the language reset.
final class ScriptPersistenceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var dir: URL!
    private var fileURL: URL { dir.appendingPathComponent("saved").appendingPathComponent("script.txt") }

    override func setUp() {
        super.setUp()
        suiteName = "script-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeState() -> TeleprompterState {
        TeleprompterState(settings: PrompterSettingsStore(defaults: defaults),
                          scriptStore: ScriptStore(fileURL: fileURL))
    }

    private func afterRelaunch(_ change: (TeleprompterState) -> Void) -> TeleprompterState {
        change(makeState())
        return makeState()
    }

    private let englishScript = "Good morning everyone. Today I want to walk you through the three things we changed this quarter, and why they matter to the people who use our product every day."
    private let germanScript = "Guten Morgen zusammen. Heute möchte ich Ihnen die drei Dinge zeigen, die wir in diesem Quartal geändert haben, und warum sie für die Menschen wichtig sind, die unser Produkt jeden Tag benutzen."

    func testPastedScriptSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.scriptText = self.germanScript }.scriptText, germanScript)
    }

    func testOpenedScriptSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.scriptText = self.englishScript }.scriptText, englishScript)
    }

    func testClearedEditorStaysEmptyAfterARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.scriptText = "" }.scriptText, "")
    }

    func testFreshInstallGetsTheSampleScript() {
        XCTAssertEqual(makeState().scriptText, TeleprompterState.defaultScript)
    }

    func testUnreadableFileFallsBackToTheSampleScript() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0xC0, 0x80, 0xFF]).write(to: fileURL)
        XCTAssertEqual(makeState().scriptText, TeleprompterState.defaultScript)
    }

    // The saved language must not beat the restored script.

    func testAutoLanguageFollowsARestoredEnglishScript() {
        let state = afterRelaunch {
            $0.recognitionLocale = "de-DE"
            $0.scriptText = self.englishScript
        }
        state.applyAutoLocaleIfNeeded()
        XCTAssertTrue(state.recognitionLocale.hasPrefix("en"), "got \(state.recognitionLocale)")
    }

    func testAutoLanguageFollowsARestoredGermanScript() {
        let state = afterRelaunch {
            $0.recognitionLocale = "en-US"
            $0.scriptText = self.germanScript
        }
        state.applyAutoLocaleIfNeeded()
        XCTAssertTrue(state.recognitionLocale.hasPrefix("de"), "got \(state.recognitionLocale)")
    }
}

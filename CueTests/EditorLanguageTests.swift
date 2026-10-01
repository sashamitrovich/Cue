import XCTest
@testable import Cue

/// #17: the editor now asks for detection as the script changes, not only at
/// Start. That makes detection run far more often, so these pin down that it
/// still never overrides a language the reader picked by hand.
final class EditorLanguageTests: XCTestCase {
    private var suiteName: String!
    private var state: TeleprompterState!

    private let portuguese = "Oi, pessoal! Hoje eu trouxe três dicas simples para quem tem medo de falar em público. A primeira é respirar antes de começar."

    override func setUp() {
        super.setUp()
        suiteName = "editor-language-\(UUID().uuidString)"
        state = TeleprompterState(settings: PrompterSettingsStore(defaults: UserDefaults(suiteName: suiteName)!))
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDetectsWithoutBuildingWords() {
        state.recognitionLocale = "en-US"
        state.scriptText = portuguese
        state.applyAutoLocaleIfNeeded()
        XCTAssertTrue(state.recognitionLocale.hasPrefix("pt"), "got \(state.recognitionLocale)")
        XCTAssertTrue(state.words.isEmpty, "detection alone must not build the script")
    }

    func testAManualPickSurvivesEveryEdit() {
        state.selectLocaleManually("de-DE")
        for n in stride(from: 10, through: portuguese.count, by: 10) {
            state.scriptText = String(portuguese.prefix(n))
            state.applyAutoLocaleIfNeeded()
        }
        XCTAssertEqual(state.recognitionLocale, "de-DE")
    }

    func testAShortFragmentDoesNotFlipTheLanguage() {
        // Typing "Oi" into an English script mustn't swing to Portuguese.
        state.recognitionLocale = "en-US"
        state.scriptText = "Oi"
        state.applyAutoLocaleIfNeeded()
        XCTAssertEqual(state.recognitionLocale, "en-US")
    }

    // MARK: - A manual pick covers only the script it was made for

    func testOpeningANewScriptDetectsAgainAfterAManualPick() {
        state.selectLocaleManually("de-DE")
        state.loadScript(portuguese)
        state.applyAutoLocaleIfNeeded()   // what the editor runs once the text lands
        XCTAssertTrue(state.recognitionLocale.hasPrefix("pt"), "got \(state.recognitionLocale)")
    }

    func testEmptyingTheEditorDetectsAgainForWhatIsTypedNext() {
        state.selectLocaleManually("de-DE")
        state.scriptText = ""
        state.scriptText = portuguese
        state.applyAutoLocaleIfNeeded()
        XCTAssertTrue(state.recognitionLocale.hasPrefix("pt"), "got \(state.recognitionLocale)")
    }

    func testEditingTheSameScriptKeepsTheManualPick() {
        state.scriptText = portuguese
        state.selectLocaleManually("de-DE")
        state.scriptText = portuguese + " E a segunda é falar devagar."
        state.applyAutoLocaleIfNeeded()
        XCTAssertEqual(state.recognitionLocale, "de-DE")
    }

    func testAManualPickSurvivesARelaunch() {
        let store = PrompterSettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        state.selectLocaleManually("de-DE")
        let relaunched = TeleprompterState(settings: store)
        relaunched.applyAutoLocaleIfNeeded()  // editor appears with the default (English) script
        XCTAssertEqual(relaunched.recognitionLocale, "de-DE")
    }

    func testADetectedLanguageSurvivesARelaunch() {
        let store = PrompterSettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        state.recognitionLocale = "en-US"
        state.loadScript(portuguese)
        state.applyAutoLocaleIfNeeded()
        let detected = state.recognitionLocale
        XCTAssertTrue(detected.hasPrefix("pt"))
        XCTAssertEqual(TeleprompterState(settings: store).recognitionLocale, detected)
    }
}

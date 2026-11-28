import XCTest
@testable import Cue

/// #17: the editor now asks for detection as the script changes, not only at
/// Start. That makes detection run far more often, so these pin down that it
/// still never churns on short fragments, and a confident different language
/// overrides a manual pick (#34).
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

    func testAShortFragmentDoesNotFlipTheLanguage() {
        // Typing "Oi" into an English script mustn't swing to Portuguese.
        state.recognitionLocale = "en-US"
        state.scriptText = "Oi"
        state.applyAutoLocaleIfNeeded()
        XCTAssertEqual(state.recognitionLocale, "en-US")
    }

    // MARK: - The script on screen decides the language, over a manual pick

    func testADetectedLanguageSurvivesARelaunch() {
        let store = PrompterSettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        state.recognitionLocale = "en-US"
        state.scriptText = portuguese
        state.applyAutoLocaleIfNeeded()
        let detected = state.recognitionLocale
        XCTAssertTrue(detected.hasPrefix("pt"))
        XCTAssertEqual(TeleprompterState(settings: store).recognitionLocale, detected)
    }

    func testPastingAnotherLanguageOverridesAManualPick() {
        state.recognitionLocale = "de-DE"
        state.scriptText = portuguese   // a paste: plain assignment
        state.applyAutoLocaleIfNeeded()
        XCTAssertTrue(state.recognitionLocale.hasPrefix("pt"), "got \(state.recognitionLocale)")
    }

    func testPastingEnglishOverridesAManualGermanPick() {
        state.recognitionLocale = "de-DE"
        state.scriptText = "Good morning everyone. Today I want to walk you through the three things we changed this quarter, and why they matter to the people who use our product every day."
        state.applyAutoLocaleIfNeeded()
        XCTAssertTrue(state.recognitionLocale.hasPrefix("en"), "got \(state.recognitionLocale)")
    }
}

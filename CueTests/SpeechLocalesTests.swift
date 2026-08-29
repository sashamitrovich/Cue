import XCTest
@testable import Cue

/// The language-picking logic is pure so it can be exercised without a
/// recogniser — the device's list is injected.
final class SpeechLocalesTests: XCTestCase {
    private let available = ["en-US", "en-GB", "de-DE", "de-AT", "nl-NL", "sr-RS", "fr-FR"]

    func testPrefersAnExactMatch() {
        XCTAssertEqual(
            SpeechLocales.preferred(available: available, current: "de-DE"),
            "de-DE"
        )
    }

    func testMatchesUnderscoreIdentifiersFromLocaleCurrent() {
        // `Locale.current.identifier` uses an underscore, the recogniser's
        // supported list uses a hyphen. They have to meet.
        XCTAssertEqual(
            SpeechLocales.preferred(available: available, current: "nl_NL"),
            "nl-NL"
        )
    }

    func testFallsBackToTheSameLanguageInAnotherRegion() {
        // An Austrian device should get German, not English.
        XCTAssertEqual(
            SpeechLocales.preferred(available: ["en-US", "de-DE"], current: "de-AT"),
            "de-DE"
        )
    }

    func testFallsBackToEnglishWhenTheLanguageIsUnsupported() {
        XCTAssertEqual(
            SpeechLocales.preferred(available: available, current: "ja-JP"),
            "en-US"
        )
    }

    func testFallsBackToEnglishWhenTheDeviceListIsEmpty() {
        XCTAssertEqual(
            SpeechLocales.preferred(available: [], current: "de-DE"),
            SpeechLocales.fallback
        )
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(
            SpeechLocales.preferred(available: ["EN-us", "de-DE"], current: "en_US"),
            "EN-us"
        )
    }

    /// The picker has to distinguish two dialects of one language, which is
    /// the whole reason the region is in the label.
    func testLabelSeparatesRegionsOfTheSameLanguage() {
        let gb = SpeechLocales.label(for: Locale(identifier: "en-GB"))
        let us = SpeechLocales.label(for: Locale(identifier: "en-US"))
        XCTAssertNotEqual(gb, us)
        XCTAssertTrue(gb.hasPrefix("English"), "got \(gb)")
        XCTAssertTrue(us.hasPrefix("English"), "got \(us)")
    }

    func testLabelSurvivesALanguageOnlyIdentifier() {
        XCTAssertFalse(SpeechLocales.label(for: Locale(identifier: "de")).isEmpty)
    }
}

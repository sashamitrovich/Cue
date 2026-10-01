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

    // MARK: - autoLocale: switching the listening language to match the script

    private let detectAvailable = ["en-US", "en-GB", "pt-BR", "it-IT", "de-DE", "fr-FR"]

    func testAutoSwitchesToTheDetectedLanguage() {
        // A Portuguese script on an English default should move to pt-BR.
        XCTAssertEqual(
            SpeechLocales.autoLocale(detected: "pt", confidence: 0.95,
                                     available: detectAvailable, current: "en-US"),
            "pt-BR"
        )
    }

    func testAutoIgnoresLowConfidence() {
        // Short or mixed text → don't guess; leave the locale alone.
        XCTAssertNil(
            SpeechLocales.autoLocale(detected: "pt", confidence: 0.2,
                                     available: detectAvailable, current: "en-US")
        )
    }

    func testAutoIgnoresUnrecognisableLanguage() {
        // Detected Japanese, but the device has no Japanese recogniser: stay put
        // rather than fall back to English and churn the locale.
        XCTAssertNil(
            SpeechLocales.autoLocale(detected: "ja", confidence: 0.99,
                                     available: detectAvailable, current: "en-US")
        )
    }

    func testAutoLeavesTheRegionAloneWhenLanguageAlreadyMatches() {
        // Reader is on pt-PT and the script is Portuguese: don't yank them to
        // pt-BR — the language is already right.
        XCTAssertNil(
            SpeechLocales.autoLocale(detected: "pt", confidence: 0.99,
                                     available: detectAvailable + ["pt-PT"], current: "pt-PT")
        )
    }

    func testAutoDoesNothingWithoutADetection() {
        XCTAssertNil(
            SpeechLocales.autoLocale(detected: nil, confidence: 0,
                                     available: detectAvailable, current: "en-US")
        )
    }

    /// The end-to-end detector should recognise an unambiguous paragraph. This
    /// one leans on NaturalLanguage, so it asserts only the language, not a
    /// confidence figure.
    func testDetectLanguageOnARealParagraph() {
        let pt = "Olá a todos, hoje vou falar sobre a nossa empresa e os resultados que alcançámos neste trimestre."
        XCTAssertEqual(SpeechLocales.detectLanguage(in: pt)?.language, "pt")
        XCTAssertNil(SpeechLocales.detectLanguage(in: "   "))
    }

    // MARK: - #17: which dialect a same-language fallback lands on

    /// The recogniser's list in its real (alphabetical) order, where the first
    /// English is en-AE and the first Italian is it-CH.
    private let realOrder = ["en-AE", "en-AU", "en-GB", "en-US", "it-CH", "it-IT",
                             "pt-BR", "pt-PT", "de-AT", "de-CH", "de-DE"]

    func testEnglishOnlyAppOnABrazilianPhoneGetsUSEnglishNotEmirati() {
        // An English-only app sees `en_BR` on a pt-BR device. This was en-AE.
        XCTAssertEqual(SpeechLocales.preferred(available: realOrder, current: "en_BR"), "en-US")
    }

    func testBareItalianLandsOnItalyNotSwitzerland() {
        XCTAssertEqual(SpeechLocales.preferred(available: realOrder, current: "it"), "it-IT")
    }

    func testRegionMatchStillBeatsThePrimaryDialect() {
        XCTAssertEqual(SpeechLocales.preferred(available: realOrder, current: "en_GB"), "en-GB")
        XCTAssertEqual(SpeechLocales.preferred(available: realOrder, current: "de_CH"), "de-CH")
    }

    func testPrimaryDialectMissingFallsToAnyOfTheLanguage() {
        XCTAssertEqual(SpeechLocales.preferred(available: ["en-US", "it-CH"], current: "it"), "it-CH")
    }

    func testAutoUsesTheDeviceRegionToPickTheDialect() {
        // Portuguese script: a Portuguese phone keeps pt-PT even though pt-BR
        // is the primary dialect; a Brazilian phone gets pt-BR.
        XCTAssertEqual(
            SpeechLocales.autoLocale(detected: "pt", confidence: 0.95, available: realOrder,
                                     current: "en-US", deviceRegion: "PT"), "pt-PT")
        XCTAssertEqual(
            SpeechLocales.autoLocale(detected: "pt", confidence: 0.95, available: realOrder,
                                     current: "en-US", deviceRegion: "BR"), "pt-BR")
    }

    func testAutoOnAForeignRegionFallsToThePrimaryDialect() {
        // Italian script on a Brazilian phone: there is no it-BR, so it-IT,
        // not the alphabetically first it-CH.
        XCTAssertEqual(
            SpeechLocales.autoLocale(detected: "it", confidence: 0.95, available: realOrder,
                                     current: "en-US", deviceRegion: "BR"), "it-IT")
    }

    // MARK: - First launch uses the phone's language (#17)

    func testFirstLaunchOnABrazilianPhoneListensInPortuguese() {
        XCTAssertEqual(SpeechLocales.firstLaunchDefault(phoneLanguage: "pt-BR", region: "BR",
                                                        available: realOrder), "pt-BR")
    }

    func testFirstLaunchFillsInTheRegionWhenTheLanguageHasNone() {
        XCTAssertEqual(SpeechLocales.firstLaunchDefault(phoneLanguage: "de", region: "AT",
                                                        available: realOrder), "de-AT")
        XCTAssertEqual(SpeechLocales.firstLaunchDefault(phoneLanguage: "it", region: "BR",
                                                        available: realOrder), "it-IT")
    }

    func testFirstLaunchWithAnUnsupportedLanguageIsUSEnglish() {
        XCTAssertEqual(SpeechLocales.firstLaunchDefault(phoneLanguage: "ja-JP", region: "JP",
                                                        available: realOrder), "en-US")
        XCTAssertEqual(SpeechLocales.firstLaunchDefault(phoneLanguage: nil, region: "AE",
                                                        available: realOrder), "en-US")
    }
}

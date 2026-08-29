import Foundation
import Speech

/// Which language the prompter listens in.
///
/// This was hard-coded to `en-US`, which meant the app worked for exactly one
/// audience: anyone reading a script in German, Dutch, Spanish or Serbian got
/// a prompter that sat perfectly still while they talked, with nothing on
/// screen to explain why. `SFSpeechRecognizer` supports dozens of locales on
/// device; the only thing missing was letting someone choose one.
///
/// The picking logic is a pure function so it can be tested without a
/// recogniser — the device list is injected rather than read here.
enum SpeechLocales {
    /// The fallback when nothing better matches, and what the app used to
    /// assume unconditionally.
    static let fallback = "en-US"

    /// Every locale this device can recognise, ordered by the name the user
    /// would look for.
    static func available() -> [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { label(for: $0) < label(for: $1) }
    }

    /// How a locale is named in the picker: the language, then the region
    /// where the same language appears more than once — "English (United
    /// Kingdom)" — since the distinction between those is exactly what the
    /// reader is choosing between.
    static func label(for locale: Locale) -> String {
        let display = Locale.current
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let languageCode = identifier.split(separator: "-").first.map(String.init) ?? identifier
        let language = display.localizedString(forLanguageCode: languageCode) ?? identifier
        guard let region = identifier.split(separator: "-").dropFirst().first.map(String.init),
              let regionName = display.localizedString(forRegionCode: region) else {
            return language.capitalized
        }
        return "\(language.capitalized) (\(regionName))"
    }

    /// The best default for someone who has never chosen: their own locale if
    /// the device can recognise it, otherwise any dialect of their language,
    /// otherwise `en-US`.
    ///
    /// - Parameters:
    ///   - available: identifiers the device supports, in any format.
    ///   - current: the identifier to match against, normally `Locale.current`.
    static func preferred(available: [String], current: String) -> String {
        let normalize = { (s: String) in s.replacingOccurrences(of: "_", with: "-").lowercased() }
        let wanted = normalize(current)
        // An exact match — "de-DE" for a German-in-Germany device.
        if let exact = available.first(where: { normalize($0) == wanted }) {
            return exact
        }
        // Same language, different region: a de-AT device should still get
        // German recognition rather than falling all the way back to English.
        let wantedLanguage = wanted.split(separator: "-").first.map(String.init) ?? wanted
        if let sameLanguage = available.first(where: {
            normalize($0).split(separator: "-").first.map(String.init) == wantedLanguage
        }) {
            return sameLanguage
        }
        return available.first(where: { normalize($0) == normalize(fallback) }) ?? fallback
    }

    /// The stored default for a fresh install, resolved against this device.
    static func systemDefault() -> String {
        preferred(
            available: SFSpeechRecognizer.supportedLocales().map(\.identifier),
            current: Locale.current.identifier
        )
    }
}

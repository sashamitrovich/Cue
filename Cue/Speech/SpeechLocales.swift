import Foundation
import NaturalLanguage
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
        let sameLanguage = available.filter {
            normalize($0).split(separator: "-").first.map(String.init) == wantedLanguage
        }
        // Not just the first one listed: the recogniser's list is alphabetical,
        // so "first English" was en-AE and "first Italian" was it-CH. An app
        // whose UI is English-only reports `en_BR` on a Brazilian phone, so this
        // branch is the common case outside English-speaking countries.
        let primary = normalize("\(wantedLanguage)-\(primaryRegion[wantedLanguage] ?? wantedLanguage)")
        if let main = sameLanguage.first(where: { normalize($0) == primary }) ?? sameLanguage.first {
            return main
        }
        return available.first(where: { normalize($0) == normalize(fallback) }) ?? fallback
    }

    /// The dialect to fall back to when a language's region can't be matched,
    /// where it isn't simply `xx-XX` (it-IT, de-DE, fr-FR…).
    private static let primaryRegion = ["en": "US", "pt": "BR", "sv": "SE", "da": "DK",
                                        "uk": "UA", "cs": "CZ", "zh": "CN", "ja": "JP",
                                        "ko": "KR", "he": "IL", "el": "GR", "ar": "SA"]

    /// The stored default for a fresh install, resolved against this device.
    ///
    /// The phone's own language, not `Locale.current`: On Cue's interface is
    /// English-only, so iOS resolves `Locale.current` to English plus the
    /// phone's region (`en_BR` on a Brazilian phone) and every new user outside
    /// English-speaking countries started out listening in English (#17).
    static func systemDefault() -> String {
        firstLaunchDefault(
            phoneLanguage: Locale.preferredLanguages.first,
            region: Locale.current.region?.identifier,
            available: SFSpeechRecognizer.supportedLocales().map(\.identifier)
        )
    }

    /// Pure core of `systemDefault`. `phoneLanguage` may carry no region
    /// ("hr"), in which case the device's region fills it in.
    static func firstLaunchDefault(phoneLanguage: String?, region: String?,
                                   available: [String]) -> String {
        guard let phoneLanguage else { return preferred(available: available, current: fallback) }
        let hasRegion = phoneLanguage.replacingOccurrences(of: "_", with: "-").contains("-")
        let wanted = hasRegion || region == nil ? phoneLanguage : "\(phoneLanguage)-\(region!)"
        return preferred(available: available, current: wanted)
    }

    // MARK: - Detecting the script's language

    /// The dominant language of `text` and the recogniser's confidence in it,
    /// or nil when the text is too short or empty to judge. A thin wrapper over
    /// `NLLanguageRecognizer`, kept apart from the pure resolver below so that
    /// stays testable without NaturalLanguage.
    static func detectLanguage(in text: String) -> (language: String, confidence: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0
        return (dominant.rawValue, confidence)
    }

    /// Which locale to auto-switch to for a script in `detected` language, or
    /// nil to leave the current one alone. Pure, so it is tested without a
    /// recogniser. The locale is left unchanged when:
    /// - detection failed (`detected == nil`),
    /// - confidence is below `minConfidence` (short or mixed-language text),
    /// - the device cannot recognise that language, or
    /// - the current locale is already that language (don't churn the region a
    ///   reader deliberately chose — pt-PT stays pt-PT for Portuguese).
    static func autoLocale(detected language: String?,
                           confidence: Double,
                           available: [String],
                           current: String,
                           deviceRegion: String? = nil,
                           minConfidence: Double = 0.6) -> String? {
        guard let language, confidence >= minConfidence else { return nil }
        let want = languageCode(of: language)
        guard !want.isEmpty else { return nil }
        if languageCode(of: current) == want { return nil }
        // Reuse the dialect-picking logic; it falls back to en-US when the
        // language is unavailable, so only switch if it truly found `want`.
        // The device's region picks the dialect: a Portuguese script on a
        // Brazilian phone wants pt-BR, on a Portuguese one pt-PT.
        let wanted = deviceRegion.map { "\(want)-\($0)" } ?? want
        let picked = preferred(available: available, current: wanted)
        guard languageCode(of: picked) == want else { return nil }
        return picked
    }

    /// The lowercased language component of a locale identifier ("pt-BR" → "pt",
    /// "nl_NL" → "nl", "en" → "en").
    private static func languageCode(of identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first
            .map { $0.lowercased() } ?? identifier.lowercased()
    }
}

import Foundation

/// Whether a script reads right to left (Arabic, Hebrew, Persian, Urdu…).
///
/// The prompter lays words out itself, one view per word, so the bidi
/// reordering iOS applies inside a single run of text never happens across
/// them: an Arabic script came out with every line's words reversed (#20).
/// The layout needs the direction stated, and this decides it from the
/// script's own letters, not the listening locale, which a reader can set to
/// anything.
enum ScriptDirection {
    /// True when most of the strongly-directional letters are right-to-left.
    /// Digits, punctuation and spaces don't count either way, so a mostly
    /// Arabic script with a brand name or a number in it stays right-to-left,
    /// and an English script quoting one Hebrew word stays left-to-right.
    static func isRightToLeft(_ text: String) -> Bool {
        var rtl = 0, ltr = 0
        for scalar in text.unicodeScalars {
            if isStrongRightToLeft(scalar) { rtl += 1 }
            else if scalar.properties.isAlphabetic { ltr += 1 }
        }
        return rtl > ltr
    }

    /// Hebrew, Arabic (with its supplement and extended blocks), Syriac,
    /// Thaana, N'Ko, and the Hebrew and Arabic presentation forms. Arabic
    /// diacritics fall in these blocks too and count with their letters.
    private static func isStrongRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF,   // Hebrew, Arabic, Syriac, Arabic Supplement, Thaana, N'Ko, Samaritan, Mandaic, Arabic Extended
             0xFB1D...0xFDFF,   // Hebrew and Arabic presentation forms A
             0xFE70...0xFEFF:   // Arabic presentation forms B
            return true
        default:
            return false
        }
    }
}

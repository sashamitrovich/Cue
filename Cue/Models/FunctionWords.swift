import Foundation

/// Reflexive function words per language — the words a reader utters constantly
/// regardless of what the script says ("the", "their", "which"; Croatian "se",
/// "je", "da"; German "der", "und", "ist"). Letting one anchor a far jump is the
/// classic prompter runaway.
///
/// This complements `TeleprompterState`'s script-frequency guard, it does not
/// replace it. Frequency catches words that recur in *this* script (any
/// language, no list needed); this catches the language's function words even
/// when they appear only once in a short script — the case frequency misses.
/// Together: a far anchor is blocked if the word is common in the script OR a
/// known function word of the recognition language.
///
/// The sets are the high-frequency function words only, not exhaustive
/// vocabularies — frequency covers the long tail. A language with no entry here
/// (an unlisted locale) simply falls back to frequency-only, which is still
/// language-agnostic and correct, just less protective on short scripts.
///
/// Entries are lowercase and match `TeleprompterState.normalize` output. Slavic
/// entries are given in the script the recogniser returns: latinica for
/// Croatian/Serbian/Bosnian, Cyrillic for Russian/Ukrainian.
enum FunctionWords {

    /// Whether `word` (already normalized, lowercase) is a function word of the
    /// language named by `locale` ("en-US", "hr-HR", "de-DE" …). Unknown
    /// languages return false, leaving the script-frequency guard as the only
    /// protection.
    static func contains(_ word: String, locale: String) -> Bool {
        let language = locale
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first
            .map { $0.lowercased() } ?? locale.lowercased()
        return byLanguage[language]?.contains(word) ?? false
    }

    /// Language code → its function words. South-Slavic latinica (hr/sr/bs)
    /// share one set, since the reader writes latinica and picks Croatian.
    static let byLanguage: [String: Set<String>] = {
        var map: [String: Set<String>] = [
            "en": english,
            "hr": southSlavicLatin, "sr": southSlavicLatin, "bs": southSlavicLatin,
            "cs": czech,
            "sk": slovak,
            "pl": polish,
            "ru": russian,
            "uk": ukrainian,
            "de": german,
            "es": spanish,
            "fr": french,
            "it": italian,
            "nl": dutch,
            "pt": portuguese,
        ]
        return map
    }()

    private static let english: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can",
        "do", "for", "from", "had", "has", "have", "he", "her", "him", "his",
        "i", "if", "in", "is", "it", "its", "me", "my", "no", "not", "of",
        "on", "or", "our", "she", "so", "that", "the", "their", "them", "then",
        "there", "these", "they", "this", "those", "to", "up", "us", "was",
        "we", "were", "what", "when", "which", "who", "will", "with", "would",
        "you", "your",
    ]

    private static let southSlavicLatin: Set<String> = [
        "i", "u", "na", "se", "je", "da", "su", "za", "od", "do", "ne", "li",
        "bi", "ce", "ili", "ali", "kao", "sam", "si", "smo", "ste", "te", "ga",
        "mu", "joj", "im", "mi", "vi", "on", "ona", "ono", "oni", "taj", "ta",
        "to", "ovaj", "ova", "ovo", "koji", "koja", "koje", "sto", "jer", "pa",
        "o", "s", "sa", "po", "uz", "kroz", "bez", "nad", "pod", "pred",
    ]

    private static let czech: Set<String> = [
        "a", "i", "v", "na", "se", "je", "ze", "s", "z", "do", "o", "k", "po",
        "za", "od", "ale", "nebo", "ktery", "ktera", "ktere", "to", "ten", "ta",
        "jsem", "jsi", "jsme", "jste", "jsou", "by", "ho", "mu", "ji", "jim",
        "my", "vy", "on", "ona", "ono", "oni", "co", "jak", "kdy", "kde",
        "protoze", "ne",
    ]

    private static let slovak: Set<String> = [
        "a", "i", "v", "na", "sa", "je", "ze", "s", "z", "do", "o", "k", "po",
        "za", "od", "ale", "alebo", "ktory", "ktora", "ktore", "to", "ten",
        "som", "si", "sme", "ste", "su", "by", "ho", "mu", "jej", "im", "my",
        "vy", "on", "ona", "ono", "oni", "co", "ako", "kedy", "kde", "lebo",
        "nie",
    ]

    private static let polish: Set<String> = [
        "i", "w", "na", "sie", "jest", "ze", "z", "do", "o", "po", "za", "od",
        "a", "ale", "lub", "ktory", "ktora", "ktore", "to", "ten", "ta",
        "jestem", "jestes", "jestesmy", "sa", "by", "go", "mu", "jej", "im",
        "my", "wy", "on", "ona", "ono", "oni", "co", "jak", "kiedy", "gdzie",
        "bo", "nie", "tak",
    ]

    private static let russian: Set<String> = [
        "и", "в", "на", "с", "к", "по", "за", "от", "о", "у", "что", "как",
        "это", "то", "он", "она", "оно", "они", "я", "ты", "мы", "вы", "не",
        "да", "но", "или", "а", "бы", "же", "ли", "из", "для", "до", "при",
        "под", "над", "без",
    ]

    private static let ukrainian: Set<String> = [
        "і", "в", "на", "з", "до", "о", "по", "за", "від", "що", "як", "це",
        "той", "він", "вона", "воно", "вони", "я", "ти", "ми", "ви", "не",
        "але", "або", "а", "б", "же", "для", "при", "під", "над", "без",
    ]

    private static let german: Set<String> = [
        "der", "die", "das", "und", "in", "zu", "den", "mit", "von", "ist",
        "im", "fur", "auf", "ein", "eine", "einen", "dem", "des", "nicht",
        "auch", "es", "an", "als", "am", "aus", "bei", "nach", "wird", "wie",
        "so", "dass", "war", "sind", "wir", "sie", "er", "ich", "du", "ihr",
        "man", "oder", "aber", "wenn", "weil", "dann", "noch", "nur", "schon",
    ]

    private static let spanish: Set<String> = [
        "el", "la", "los", "las", "un", "una", "de", "del", "y", "o", "en",
        "a", "que", "es", "son", "no", "se", "su", "sus", "por", "para", "con",
        "como", "mas", "pero", "si", "ya", "lo", "le", "les", "me", "te", "nos",
        "mi", "tu", "el", "ella", "ellos", "este", "esta", "esto", "muy",
        "cuando", "donde",
    ]

    private static let french: Set<String> = [
        "le", "la", "les", "un", "une", "des", "de", "du", "et", "ou", "en",
        "a", "que", "qui", "est", "sont", "ne", "pas", "se", "sa", "son", "ses",
        "pour", "par", "avec", "comme", "plus", "mais", "si", "ce", "cette",
        "cet", "je", "tu", "il", "elle", "nous", "vous", "ils", "on", "y", "ou",
        "quand", "dont",
    ]

    private static let italian: Set<String> = [
        "il", "la", "i", "le", "un", "una", "di", "e", "o", "in", "a", "che",
        "e", "sono", "non", "si", "sua", "suo", "per", "con", "come", "piu",
        "ma", "se", "lo", "gli", "mi", "ti", "ci", "io", "tu", "lui", "lei",
        "noi", "voi", "loro", "questo", "questa", "quando", "dove", "perche",
    ]

    private static let dutch: Set<String> = [
        "de", "het", "een", "en", "of", "in", "op", "te", "van", "met", "is",
        "zijn", "niet", "ik", "je", "jij", "hij", "zij", "wij", "we", "ze",
        "dat", "die", "dit", "deze", "voor", "aan", "bij", "naar", "door",
        "over", "maar", "als", "dan", "ook", "nog", "wel", "waar", "wanneer",
        "omdat", "dus",
    ]

    private static let portuguese: Set<String> = [
        "o", "a", "os", "as", "um", "uma", "de", "do", "da", "dos", "das", "e",
        "ou", "em", "no", "na", "que", "e", "sao", "nao", "se", "seu", "sua",
        "por", "para", "com", "como", "mais", "mas", "se", "ja", "lhe", "me",
        "te", "nos", "meu", "tu", "ele", "ela", "eles", "este", "esta", "isto",
        "quando", "onde",
    ]
}

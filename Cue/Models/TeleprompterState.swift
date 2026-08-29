import Foundation

struct ScriptWord: Identifiable {
    let id: Int
    let raw: String
    let norm: String
}

/// One line of the script as typed. Blank lines are kept as empty entries so
/// the prompter can reproduce the spacing from the editor — deliberate gaps
/// are useful as ad-lib room.
struct ScriptLine: Identifiable {
    let id: Int
    let words: [ScriptWord]

    var isBlank: Bool { words.isEmpty }
}

enum WordState {
    case upcoming, active, spoken
}

/// How script lines are laid out horizontally. `justified` spreads a
/// wrapped row's words to fill the width, matching print convention (the
/// last row of a paragraph is left as-is rather than stretched).
enum ScriptAlignment: String, CaseIterable, Identifiable {
    case leading, center, trailing, justified

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        case .justified: "text.justify"
        }
    }
}

/// Holds the script, playback settings, and the word-matching cursor.
/// The matching logic in `ingest(transcriptWords:)` is a direct port of the
/// sliding-window fuzzy matcher from the original web prototype.
final class TeleprompterState: ObservableObject {
    @Published var scriptText: String = TeleprompterState.defaultScript
    /// Every word in reading order — what the matcher walks.
    @Published var words: [ScriptWord] = []
    /// The same words grouped as typed, so layout can honour line breaks.
    @Published var lines: [ScriptLine] = []
    @Published var activeIndex: Int = 0
    @Published var fontSize: CGFloat = 32 {
        didSet { if persistsSettings { settings.set(.fontSize, Double(fontSize)) } }
    }
    @Published var mirror: Bool = false {
        didSet { if persistsSettings { settings.set(.mirror, mirror) } }
    }
    @Published var textAlignment: ScriptAlignment = .leading {
        didSet { if persistsSettings { settings.set(.textAlignment, textAlignment.rawValue) } }
    }
    /// Recording yourself is the common case, so the camera starts on and is
    /// turned off from the prompter, where you can see what it does.
    /// UI tests opt out: the simulator has no camera, and the permission
    /// prompt would block the run.
    @Published var cameraEnabled: Bool = !ProcessInfo.processInfo.arguments.contains("-uiTestingNoCamera") {
        didSet { if persistsSettings { settings.set(.cameraEnabled, cameraEnabled) } }
    }
    /// How opaque the scrolling script text is, so the camera feed behind it
    /// can show through more or less — 1.0 is fully opaque text, lower
    /// values let more of the live camera preview read through.
    @Published var textOpacity: Double = 1.0 {
        didSet { if persistsSettings { settings.set(.textOpacity, textOpacity) } }
    }
    /// Where the reading line sits, as a fraction of screen height. Kept high
    /// by default so the words are close to the front lens and your eyes read
    /// near the camera rather than down the screen.
    @Published var cueLineFraction: Double = 0.18 {
        didSet { if persistsSettings { settings.set(.cueLineFraction, cueLineFraction) } }
    }
    /// How far the script sits from the sides of the screen. A floor, not an
    /// addition — see `ScriptMargins`.
    @Published var sideMargin: CGFloat = ScriptMargins.default {
        didSet { if persistsSettings { settings.set(.sideMargin, Double(sideMargin)) } }
    }
    /// How much the camera feed is darkened behind the script. Higher values
    /// buy text contrast at the cost of a dimmer preview.
    @Published var cameraDimming: Double = 0.34 {
        didSet { if persistsSettings { settings.set(.cameraDimming, cameraDimming) } }
    }
    @Published var isListening: Bool = false
    /// The delivery pace used to estimate how long the script runs, until
    /// enough of a take has been spoken to measure the real one.
    @Published var targetWPM: Double = ReadingPace.defaultWPM {
        didSet { if persistsSettings { settings.set(.targetWPM, targetWPM) } }
    }
    /// Seconds counted down before listening starts, so there's time to settle
    /// and look at the lens. Zero means start immediately.
    @Published var countdownSeconds: Int = 3 {
        didSet { if persistsSettings { settings.set(.countdownSeconds, countdownSeconds) } }
    }
    /// Whether the timing readout is shown over the prompter.
    @Published var showTiming: Bool = true {
        didSet { if persistsSettings { settings.set(.showTiming, showTiming) } }
    }
    /// Whether spoken instructions ("scroll up") steer the prompter.
    @Published var voiceCommandsEnabled: Bool = true {
        didSet { if persistsSettings { settings.set(.voiceCommandsEnabled, voiceCommandsEnabled) } }
    }
    /// The dimmest already-read text is drawn — see `ReadTextFade`.
    @Published var readTextFloor: Double = ReadTextFade.defaultFloor {
        didSet { if persistsSettings { settings.set(.readTextFloor, readTextFloor) } }
    }
    /// The language the prompter listens in. Defaults to the reader's own
    /// where this device can recognise it — see `SpeechLocales`.
    @Published var recognitionLocale: String = SpeechLocales.systemDefault() {
        didSet { if persistsSettings { settings.set(.recognitionLocale, recognitionLocale) } }
    }

    private let settings: PrompterSettingsStore
    /// Off during UI tests (same flag that keeps the camera off for them) so
    /// a test run always sees compiled-in defaults, never whatever a
    /// previous run — test or real — left in this simulator's defaults.
    private let persistsSettings: Bool

    init(settings: PrompterSettingsStore = PrompterSettingsStore()) {
        self.settings = settings
        persistsSettings = !ProcessInfo.processInfo.arguments.contains("-uiTestingNoCamera")
        guard persistsSettings else { return }
        fontSize = CGFloat(settings.double(.fontSize, default: Double(fontSize)))
        mirror = settings.bool(.mirror, default: mirror)
        textAlignment = ScriptAlignment(rawValue: settings.string(.textAlignment, default: textAlignment.rawValue)) ?? textAlignment
        cameraEnabled = settings.bool(.cameraEnabled, default: cameraEnabled)
        textOpacity = settings.double(.textOpacity, default: textOpacity)
        cueLineFraction = settings.double(.cueLineFraction, default: cueLineFraction)
        sideMargin = CGFloat(settings.double(.sideMargin, default: Double(sideMargin)))
        cameraDimming = settings.double(.cameraDimming, default: cameraDimming)
        targetWPM = settings.double(.targetWPM, default: targetWPM)
        countdownSeconds = settings.int(.countdownSeconds, default: countdownSeconds)
        showTiming = settings.bool(.showTiming, default: showTiming)
        voiceCommandsEnabled = settings.bool(.voiceCommandsEnabled, default: voiceCommandsEnabled)
        readTextFloor = settings.double(.readTextFloor, default: readTextFloor)
        recognitionLocale = settings.string(.recognitionLocale, default: recognitionLocale)
    }

    static let countdownOptions = [0, 3, 5, 10]

    /// Words still ahead of the cursor. The active word counts as unread —
    /// it's the one being said, not one that's been said.
    var wordsRemaining: Int { max(0, words.count - activeIndex) }
    var wordsRead: Int { min(activeIndex, words.count) }

    /// How far through the script the cursor is, 0...1.
    var progress: Double {
        guard words.count > 1 else { return 0 }
        return Double(activeIndex) / Double(words.count - 1)
    }

    /// Counts words in arbitrary script text, for estimating a run time before
    /// `buildWords` has been called (the setup screen, as you type).
    static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Tokenizes the script into a flat word list for matching, and in parallel
    /// groups those same words by the lines they were typed on so the prompter
    /// can reproduce the editor's line breaks and blank lines.
    func buildWords() {
        var flat: [ScriptWord] = []
        var built: [ScriptLine] = []

        // Normalize line endings first: splitting CRLF on a newline character
        // set would treat each "\r\n" as two breaks and invent a blank line
        // between every line of a Windows-authored or imported file.
        let normalized = scriptText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for (lineIndex, rawLine) in normalized.components(separatedBy: "\n").enumerated() {
            let tokens = rawLine.split(whereSeparator: { $0.isWhitespace })
            let lineWords = tokens.map { token -> ScriptWord in
                let word = ScriptWord(
                    id: flat.count,
                    raw: String(token),
                    norm: Self.normalize(String(token))
                )
                flat.append(word)
                return word
            }
            built.append(ScriptLine(id: lineIndex, words: lineWords))
        }

        // Trailing blank lines would only add dead space at the end.
        while let last = built.last, last.isBlank {
            built.removeLast()
        }

        words = flat
        lines = built
        activeIndex = 0
        unmatchedWords = 0
    }

    /// Moves the cursor by whole lines, for "scroll up" / "scroll down".
    ///
    /// Lines rather than words because that is what a reader means by going
    /// back: the unit you re-read is a line, and landing mid-sentence would be
    /// worse than not moving. Blank lines are skipped — they are ad-lib space,
    /// not something to land on.
    func moveCursor(lines delta: Int) {
        guard !words.isEmpty, delta != 0 else { return }
        let populated = lines.filter { !$0.isBlank }
        guard !populated.isEmpty else { return }

        let current = populated.lastIndex { line in
            (line.words.first?.id ?? 0) <= activeIndex
        } ?? 0
        let target = min(max(current + delta, 0), populated.count - 1)
        activeIndex = populated[target].words.first?.id ?? 0
    }

    /// The normalized words at and just after the cursor, so a spoken command
    /// can be checked against what the script actually says next.
    func upcomingWords(_ count: Int) -> [String] {
        guard !words.isEmpty else { return [] }
        let start = min(max(activeIndex, 0), words.count - 1)
        return words[start..<min(start + count, words.count)].map(\.norm)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" }
    }

    func state(for index: Int) -> WordState {
        if index < activeIndex { return .spoken }
        if index == activeIndex { return .active }
        return .upcoming
    }

    /// Words so common they recur throughout any script. Letting one of these
    /// match far ahead of the cursor is a major cause of the prompter lurching
    /// forward — hearing "the" should never skip ten words to reach a later
    /// "the". They can still match at or next to the cursor, which is where
    /// they land during normal sequential reading.
    private static let filler: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can",
        "do", "for", "from", "had", "has", "have", "he", "her", "him", "his",
        "i", "if", "in", "is", "it", "its", "me", "my", "no", "not", "of",
        "on", "or", "our", "she", "so", "that", "the", "their", "them", "then",
        "there", "they", "this", "to", "up", "us", "was", "we", "were", "what",
        "when", "which", "who", "will", "with", "you", "your"
    ]

    /// How far ahead of the cursor a filler word is allowed to match.
    private static let fillerReach = 1
    /// The ordinary look-ahead, for someone reading roughly what is written.
    private static let window = 12
    /// The look-ahead once the reader has clearly gone off-script.
    private static let wideWindow = 60
    /// Unmatched heard words before the search widens to `wideWindow`. At a
    /// normal speaking pace this is about two seconds of speech that the
    /// script cannot account for.
    private static let missesBeforeWidening = 4
    /// ...and before it gives up on locality entirely and searches the rest
    /// of the script.
    private static let missesBeforeGlobal = 12
    /// Shortest word allowed to re-anchor the cursor beyond the ordinary
    /// window. A long jump on a short word is how the prompter runs away.
    private static let minimumAnchorLength = 4

    /// Heard words that have found nothing since the cursor last moved.
    ///
    /// Drives the widening above. Skipping a sentence, paraphrasing a clause
    /// or being misheard all look the same from here: words arrive and none
    /// of them are in the window. Without this the cursor simply stops and
    /// waits forever for words that are never going to be said — the script
    /// sits still while the reader keeps talking, which is the worst failure
    /// this app has.
    private var unmatchedWords = 0

    /// How far ahead to look, given how lost we currently are.
    private var searchReach: Int {
        if unmatchedWords >= Self.missesBeforeGlobal { return words.count }
        if unmatchedWords >= Self.missesBeforeWidening { return Self.wideWindow }
        return Self.window
    }

    /// Advances `activeIndex` by fuzzy-matching heard words against a window
    /// of upcoming script words, so partial/garbled recognition results still
    /// move the cursor forward correctly.
    ///
    /// Expects only newly heard words — see `TranscriptDeltaTracker`. Passing a
    /// cumulative transcript repeatedly would re-scan consumed words and drive
    /// the cursor too far forward.
    func ingest(transcriptWords heard: [String]) {
        guard !words.isEmpty else { return }
        var cursor = activeIndex
        var considered = 0
        for rawWord in heard {
            let word = Self.normalize(rawWord)
            guard !word.isEmpty else { continue }
            considered += 1
            let limit = min(words.count, cursor + searchReach)
            var found = -1
            var j = cursor
            while j < limit {
                let nw = words[j].norm
                if !nw.isEmpty {
                    if nw == word
                        || (word.count > 3 && nw.hasPrefix(word))
                        || (nw.count > 3 && word.hasPrefix(nw)) {
                        found = j
                        break
                    }
                }
                j += 1
            }
            guard found >= 0 else { continue }
            if found - cursor > Self.fillerReach && Self.filler.contains(word) {
                continue
            }
            // Past the ordinary window this is no longer sequential reading —
            // it is a re-anchor after a deviation, and it needs a word
            // distinctive enough to be worth trusting. Anchoring a
            // fifty-word jump on "slide" or "so" is how a prompter runs away
            // from its reader.
            if found - cursor > Self.window, word.count < Self.minimumAnchorLength {
                continue
            }
            cursor = found + 1
        }
        if cursor > activeIndex {
            activeIndex = min(cursor, words.count - 1)
            unmatchedWords = 0
        } else {
            unmatchedWords += considered
        }
    }

    /// Forgets how lost the matcher was. For anything that moves the cursor
    /// deliberately — a restart, a drag, a voice command — since the reader
    /// has just said where they are.
    func resyncMatcher() {
        unmatchedWords = 0
    }

    /// Mark Twain, "Advice to Youth" (1882) — a real speech, and one written
    /// to be *said* rather than read, which is what this app is for. Long
    /// enough to scroll properly, funny enough that testing it repeatedly is
    /// no hardship, and firmly in the public domain. It replaced a script
    /// that explained the app to itself, which demonstrated nothing about
    /// reading aloud; the "?" guide and the first-run voice-command tip carry
    /// the onboarding instead.
    static let defaultScript = """
    Being told I would be expected to talk here, I inquired what sort of a talk I ought to make. They said it should be something suitable to youth — something didactic, instructive, or something in the nature of good advice.

    Very well. I have a few things in my mind which I have often longed to say for the instruction of the young; for it is in one's tender early years that such things will best take root and be most enduring and most valuable.

    First, then. I will say to you, my young friends — and I say it beseechingly, urgingly —

    Always obey your parents, when they are present. This is the best policy in the long run, because if you don't they will make you. Most parents think they know better than you do, and you can generally make more by humoring that superstition than you can by acting on your own better judgment.

    Be respectful to your superiors, if you have any, also to strangers, and sometimes to others. If a person offend you, and you are in doubt as to whether it was intentional or not, do not resort to extreme measures; simply watch your chance and hit him with a brick.

    — Mark Twain, "Advice to Youth", 1882
    """
}

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
    @Published var fontSize: CGFloat = 32
    @Published var driftIndex: Int = 0
    @Published var mirror: Bool = false
    @Published var textAlignment: ScriptAlignment = .leading
    /// Recording yourself is the common case, so the camera starts on and is
    /// turned off from the prompter, where you can see what it does.
    /// UI tests opt out: the simulator has no camera, and the permission
    /// prompt would block the run.
    @Published var cameraEnabled: Bool = !ProcessInfo.processInfo.arguments.contains("-uiTestingNoCamera")
    @Published var manualMode: Bool = false
    /// How opaque the scrolling script text is, so the camera feed behind it
    /// can show through more or less — 1.0 is fully opaque text, lower
    /// values let more of the live camera preview read through.
    @Published var textOpacity: Double = 1.0
    /// Where the reading line sits, as a fraction of screen height. Kept high
    /// by default so the words are close to the front lens and your eyes read
    /// near the camera rather than down the screen.
    @Published var cueLineFraction: Double = 0.18
    /// How far the script sits from the sides of the screen. A floor, not an
    /// addition — see `ScriptMargins`.
    @Published var sideMargin: CGFloat = ScriptMargins.default
    /// How much the camera feed is darkened behind the script. Higher values
    /// buy text contrast at the cost of a dimmer preview.
    @Published var cameraDimming: Double = 0.34
    @Published var isListening: Bool = false
    /// The delivery pace used to estimate how long the script runs, until
    /// enough of a take has been spoken to measure the real one.
    @Published var targetWPM: Double = ReadingPace.defaultWPM
    /// Seconds counted down before listening starts, so there's time to settle
    /// and look at the lens. Zero means start immediately.
    @Published var countdownSeconds: Int = 3
    /// Whether the timing readout is shown over the prompter.
    @Published var showTiming: Bool = true
    /// Whether spoken instructions ("scroll up") steer the prompter.
    @Published var voiceCommandsEnabled: Bool = true
    /// The dimmest already-read text is drawn — see `ReadTextFade`.
    @Published var readTextFloor: Double = ReadTextFade.defaultFloor

    static let countdownOptions = [0, 3, 5, 10]

    static let driftSteps: [CGFloat] = [0, 8, 16, 26, 40]
    static let driftLabels = ["Off", "Slow", "Easy", "Medium", "Fast"]

    var driftSpeed: CGFloat { Self.driftSteps[driftIndex] }
    var driftLabel: String { Self.driftLabels[driftIndex] }

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
    private static let window = 12

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
        for rawWord in heard {
            let word = Self.normalize(rawWord)
            guard !word.isEmpty else { continue }
            let limit = min(words.count, cursor + Self.window)
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
            cursor = found + 1
        }
        if cursor > activeIndex {
            activeIndex = min(cursor, words.count - 1)
        }
    }

    static let defaultScript = """
    Welcome, and thank you for being here today. I want to start with a simple idea, one that took me years to understand. The words you rehearse are never the words you deliver.

    Something changes the moment a room is listening. So instead of memorizing every line, learn the shape of your story. Know where it starts, know where it turns, and know exactly how it ends. Everything in between is a conversation. Let's begin.
    """
}

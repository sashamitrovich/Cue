import Foundation

/// Spoken instructions to the prompter itself.
enum VoiceCommand: Equatable {
    /// Step the reading cursor back a line, so a line can be re-read.
    case back
    /// Step it forward a line.
    case forward

    var lineOffset: Int {
        switch self {
        case .back: return -1
        case .forward: return 1
        }
    }
}

/// Picks commands out of the stream of heard words before the matcher sees it.
///
/// Two things make this less trivial than matching a phrase:
///
/// 1. **Command words must be swallowed.** If "scroll up" reached the matcher
///    it would try to match those words against the script and drag the cursor
///    along — the command would fight the thing it just did.
/// 2. **A phrase can straddle two callbacks.** Recognition delivers words in
///    whatever chunks it likes, so "scroll" can arrive in one delta and "up"
///    in the next. The opening word of a possible command is therefore held
///    back for one word, and released if what follows doesn't complete it.
///
/// A reference type because it is mutated from the recognition callback.
final class VoiceCommandDetector {
    private static let phrases: [([String], VoiceCommand)] = [
        (["scroll", "up"], .back),
        (["scroll", "back"], .back),
        (["go", "back"], .back),
        (["scroll", "down"], .forward),
        (["go", "on"], .forward)
    ]
    private static let longestPhrase = 2

    /// Command words are matched loosely, like script words are.
    ///
    /// Recognition of a short phrase is *harder* than of running speech — it
    /// has no surrounding context to disambiguate — so requiring an exact
    /// match made commands the strictest thing in the app, which is backwards.
    /// "scrawl up" and "scrolled up" should steer the prompter.
    static func matches(_ heard: String, _ expected: String) -> Bool {
        if heard == expected { return true }
        // Same prefix rule the script matcher uses.
        if expected.count > 3 && (heard.hasPrefix(expected) || expected.hasPrefix(heard)) { return true }
        // One or two letters out, for longer words only — "up" must not match
        // "on", or every other word would be a command.
        guard expected.count >= 5 else { return false }
        return editDistance(heard, expected) <= 2
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Words held back because they might be the start of a command.
    private var held: [String] = []

    /// Splits heard words into commands to run and words to match against the
    /// script.
    ///
    /// - Parameter scriptAhead: the normalized words at and just after the
    ///   cursor. When the script itself says "scroll up" at this point, the
    ///   script wins — a teleprompter must be able to read a sentence about
    ///   scrolling without steering itself.
    func process(_ heard: [String], scriptAhead: [String] = []) -> (commands: [VoiceCommand], passthrough: [String]) {
        var commands: [VoiceCommand] = []
        var passthrough: [String] = []
        var buffer = held + heard.map(TeleprompterState.normalize).filter { !$0.isEmpty }
        held = []

        while !buffer.isEmpty {
            if let (phrase, command) = Self.phrases.first(where: { starts(buffer, with: $0.0) }) {
                if scriptSays(phrase, scriptAhead: scriptAhead) {
                    // The script really does say this — read it, don't obey it.
                    passthrough.append(buffer.removeFirst())
                    continue
                }
                commands.append(command)
                buffer.removeFirst(phrase.count)
                continue
            }
            // Could this still become a command once more words arrive?
            if buffer.count < Self.longestPhrase,
               Self.phrases.contains(where: { phrase in
                   zip(phrase.0, buffer).allSatisfy { Self.matches($1, $0) }
               }) {
                held = buffer
                break
            }
            passthrough.append(buffer.removeFirst())
        }
        return (commands, passthrough)
    }

    /// Anything held back is released when listening stops, so a half-command
    /// doesn't reappear at the start of the next take.
    func reset() {
        held = []
    }

    private func starts(_ buffer: [String], with phrase: [String]) -> Bool {
        guard buffer.count >= phrase.count else { return false }
        return zip(phrase, buffer).allSatisfy { Self.matches($1, $0) }
    }

    private func scriptSays(_ phrase: [String], scriptAhead: [String]) -> Bool {
        guard scriptAhead.count >= phrase.count else { return false }
        return Array(scriptAhead.prefix(phrase.count)) == phrase
    }
}

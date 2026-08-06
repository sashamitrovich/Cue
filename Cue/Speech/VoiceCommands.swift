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
        (["scroll", "down"], .forward)
    ]
    private static let longestPhrase = 2

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
            if let (phrase, command) = Self.phrases.first(where: { buffer.starts(with: $0.0) }) {
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
               Self.phrases.contains(where: { $0.0.starts(with: buffer) }) {
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

    private func scriptSays(_ phrase: [String], scriptAhead: [String]) -> Bool {
        guard scriptAhead.count >= phrase.count else { return false }
        return Array(scriptAhead.prefix(phrase.count)) == phrase
    }
}

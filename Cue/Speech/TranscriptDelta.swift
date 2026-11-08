import Foundation

/// Tracks how much of a recognition task's transcript has already been handed
/// to the matcher.
///
/// `SFSpeechRecognitionResult.bestTranscription.formattedString` is cumulative
/// — every partial result repeats the whole transcript for the current task,
/// not just the newly heard words. Feeding that whole string to the matcher on
/// each callback makes it re-scan words it already consumed, and since each
/// heard word may match anywhere in the look-ahead window, the cursor lurches
/// forward. This hands over only the newly appended tail.
struct TranscriptDeltaTracker {
    private var emittedCount = 0
    /// First word of the previous transcript, to tell a reset (a new utterance
    /// starts with a different word) from a revision (the start is stable).
    private var firstWord: String?

    /// A transcript must have at least this many words handed over before a
    /// collapse can be read as a reset: a short one shrinks by revision all the
    /// time (three guesses becoming one), and replaying it would feed the
    /// matcher words it has just used.
    private static let minimumWordsForReset = 6

    /// Returns only the words appended since the last call.
    ///
    /// `detectsReset` is for the classic recogniser, which restarts its running
    /// transcript at a pause **inside one task, without `isFinal`** (#29): at
    /// every paragraph break of a 147 s recording the transcript fell from
    /// dozens of words to one or two. That is new speech, not a correction, so
    /// the whole of it is returned; treating it as a revision threw away the
    /// first word of every paragraph. A reset is a collapse to under half of
    /// what had been handed over (half or less) *and* starting with a different
    /// word than before — ordinary revisions (words merging, "one
    /// point two" becoming "1.2") shrink the transcript by a word or two and
    /// stay revisions. The analyzer path rebuilds its transcript itself
    /// (`TranscriptAssembler`) and never resets, so it leaves this off.
    ///
    /// Known gaps, both of which lose words rather than replay them: a reset
    /// that starts with the same word the previous transcript started with
    /// ("And…" after "And…") looks like a revision; and a reset that arrives as
    /// long as, or longer than, the old transcript, or between half and full
    /// length, is treated as a revision and returns nothing. The tracker only
    /// counts words, so it cannot tell.
    mutating func newWords(in transcript: [String], detectsReset: Bool = false) -> [String] {
        // Compared the way the matcher compares words, so "So," and "so" are one.
        let first = transcript.first
            .map(TeleprompterState.normalize)
            .flatMap { $0.isEmpty ? nil : $0 }
        defer { firstWord = first }
        if detectsReset,
           emittedCount >= Self.minimumWordsForReset,
           transcript.count * 2 <= emittedCount,
           first != nil, first != firstWord {
            emittedCount = transcript.count
            return transcript
        }
        if transcript.count < emittedCount {
            // The recognizer revised its hypothesis and the transcript got
            // shorter. Re-sync without replaying anything.
            emittedCount = transcript.count
            return []
        }
        let appended = Array(transcript[emittedCount...])
        emittedCount = transcript.count
        return appended
    }

    /// Call when a new recognition task starts — its transcript restarts empty.
    mutating func reset() {
        emittedCount = 0
        firstWord = nil
    }
}

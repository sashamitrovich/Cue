import Foundation

/// Rebuilds one running transcript from `SpeechTranscriber`'s results (#25).
///
/// `SFSpeechRecognizer` hands over the whole transcript of the current task on
/// every result, which is what `TranscriptDeltaTracker` expects. The iOS 26
/// analyzer does not: each result covers only a stretch of audio. A
/// *volatile* result is a guess at the stretch not yet finalized, and the next
/// volatile result replaces it; a *final* result fixes that stretch for good,
/// and the volatile guess for it is dropped. Joining the two gives the same
/// cumulative shape as before, so the delta tracker and the matcher behind it
/// do not need to know which engine is listening.
struct TranscriptAssembler {
    private var finalized: [String] = []
    private var volatile: [String] = []

    /// Applies one result and returns the whole transcript so far.
    mutating func apply(_ text: String, isFinal: Bool) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if isFinal {
            finalized += words
            volatile = []
        } else {
            volatile = words
        }
        return finalized + volatile
    }

    mutating func reset() {
        finalized = []
        volatile = []
    }
}

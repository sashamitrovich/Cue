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

    /// Returns only the words appended since the last call.
    mutating func newWords(in transcript: [String]) -> [String] {
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
    }
}

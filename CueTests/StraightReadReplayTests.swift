import XCTest
@testable import Cue

/// Replays a real recording of someone reading a script straight through (no
/// skips, no ad-lib) and checks that the prompter keeps up with them (#29).
///
/// The fixture is what the on-device recogniser reported while the recording
/// was streamed to it at real speed, one entry per result callback, plus the
/// script position the reader was really at (`truth`, worked out offline from
/// the recogniser's own word timings). It holds the script text, so it lives in
/// `CueTests/LocalFixtures/` (gitignored) and these tests skip when it is
/// absent — they guard the author's machine, not CI.
///
/// "Position" means the same thing on both sides: the index of the next script
/// word to be read, which is what `activeIndex` is.
final class StraightReadReplayTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Callback: Decodable { let t: Double; let text: String; let truth: Int }
        let locale: String
        let script: String
        let callbacks: [Callback]
    }

    private struct Result {
        var maxLag = 0, maxLagAt = 0.0
        var maxLead = 0, lagSum = 0
        var finalCursor = 0, finalTruth = 0
        var longestFreeze = 0.0, longestFreezeAt = 0.0
        var worstHandover = 0.0, worstHandoverWord = ""
        var count = 0
        var meanLag: Double { count == 0 ? 0 : Double(lagSum) / Double(count) }
    }

    private func load(_ name: String) throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("LocalFixtures/\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local fixture \(name).json is not present")
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Feeds every callback through exactly what `SpeechTracker` does with a
    /// classic-engine result: split on spaces, take the newly appended words,
    /// hand them to the matcher.
    private func replay(_ f: Fixture) -> Result {
        let state = TeleprompterState()
        state.scriptText = f.script
        state.buildWords()
        var delta = TranscriptDeltaTracker()
        var r = Result()
        var lastMove = 0.0, lastCursor = 0
        // The last word of every paragraph (a line followed by a blank one). The
        // gap after it is where the reader pauses, so the highlight must not
        // linger on that last word once they have said it.
        var paragraphEnds: [Int] = []
        var seen = 0
        let scriptLines = f.script.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (i, line) in scriptLines.enumerated() {
            let n = line.split(whereSeparator: { $0.isWhitespace }).count
            guard n > 0 else { continue }
            seen += n
            if i + 1 < scriptLines.count,
               scriptLines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty { paragraphEnds.append(seen - 1) }
        }
        var readerPassed: [Int: Double] = [:], cursorPassed: [Int: Double] = [:]
        for cb in f.callbacks {
            let words = cb.text.split(separator: " ").map(String.init)
            let appended = delta.newWords(in: words, detectsReset: true)
            if !appended.isEmpty { state.ingest(transcriptWords: appended) }
            let cursor = state.activeIndex
            if cursor != lastCursor { lastCursor = cursor; lastMove = cb.t }
            // A freeze only counts while the reader is still moving on.
            if cb.truth > cursor + 3, cb.t - lastMove > r.longestFreeze {
                r.longestFreeze = cb.t - lastMove; r.longestFreezeAt = cb.t
            }
            let lag = cb.truth - cursor
            r.lagSum += lag; r.count += 1
            if lag > r.maxLag { r.maxLag = lag; r.maxLagAt = cb.t }
            r.maxLead = max(r.maxLead, -lag)
            r.finalCursor = cursor; r.finalTruth = cb.truth
            for end in paragraphEnds {
                if readerPassed[end] == nil, cb.truth > end { readerPassed[end] = cb.t }
                if cursorPassed[end] == nil, cursor > end { cursorPassed[end] = cb.t }
            }
        }
        for end in paragraphEnds {
            // A paragraph the reader got through but the cursor never did counts
            // from when the reader passed it to the end of the recording.
            guard let said = readerPassed[end] else { continue }
            let delay = (cursorPassed[end] ?? f.callbacks.last!.t) - said
            if delay > r.worstHandover {
                r.worstHandover = delay
                r.worstHandoverWord = f.script.split(whereSeparator: { $0.isWhitespace }).indices.contains(end)
                    ? String(f.script.split(whereSeparator: { $0.isWhitespace })[end]) : "?"
            }
        }
        return r
    }

    func testStraightReadKeepsUpWithTheReader() throws {
        let f = try load("straight-read")
        let r = replay(f)
        let summary = String(format: "[straight-read] maxLag=%d words at %.1fs, meanLag=%.1f, maxLead=%d, longestFreeze=%.1fs at %.1fs, final cursor %d vs truth %d, worstParagraphEndDelay=%.1fs on \"%@\"",
                             r.maxLag, r.maxLagAt, r.meanLag, r.maxLead, r.longestFreeze, r.longestFreezeAt, r.finalCursor, r.finalTruth, r.worstHandover, r.worstHandoverWord)
        print(summary)
        // Parallel test runs swallow stdout; leave the numbers where they can be read.
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("LocalFixtures/last-run.txt")
        try? summary.write(to: out, atomically: true, encoding: .utf8)

        // About 2.5 s of speech at a normal pace. The recogniser itself runs a
        // second or so behind the voice, so some lag is unavoidable.
        XCTAssertLessThanOrEqual(r.maxLag, 8,
            "The prompter fell \(r.maxLag) words behind the reader at \(r.maxLagAt)s")
        // The recogniser itself goes quiet for up to 1.9 s in this recording
        // (measured: the longest gap between results that carry new words), so
        // no matcher can do better than that; the rest of this allowance is
        // two misheard words and the time to recognise the third.
        XCTAssertLessThanOrEqual(r.longestFreeze, 3.5,
            "The prompter sat still for \(r.longestFreeze)s at \(r.longestFreezeAt)s while the reader kept going")
        // The highlight must leave a paragraph's last word shortly after it is
        // said, and land on the next line past the blank one.
        XCTAssertLessThanOrEqual(r.worstHandover, 1.5,
            "The highlight stayed on \"\(r.worstHandoverWord)\" for \(r.worstHandover)s after the reader had finished that paragraph")
        // Reading straight through, nothing justifies running ahead.
        XCTAssertLessThanOrEqual(r.maxLead, 3, "The prompter ran \(r.maxLead) words ahead of the reader")
        XCTAssertLessThanOrEqual(abs(r.finalCursor - r.finalTruth), 5, "It must finish where the reader finished")
    }
}

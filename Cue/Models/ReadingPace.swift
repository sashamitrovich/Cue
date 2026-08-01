import Foundation

/// Timing maths for the prompter: how long a script should take, how fast the
/// speaker is actually going, and how much is left.
///
/// Pure and date-injected so it can be unit tested — nothing here touches a
/// clock, a timer or any view state.
enum ReadingPace {
    /// A conversational delivery pace. Broadcast reads sit around 150 wpm and
    /// unhurried presentation around 130, so this is a middle default that
    /// most people can adjust from rather than fight.
    static let defaultWPM: Double = 140
    static let wpmRange: ClosedRange<Double> = 90...220

    /// Below this much evidence the measured pace is noise — the first few
    /// words of a take arrive in a burst and would report an absurd wpm.
    static let minMeasuredWords = 15
    static let minMeasuredSeconds: TimeInterval = 8

    /// Bounds on the *measured* pace. A long silence mid-take would otherwise
    /// drag the average toward zero and report a wildly inflated time left.
    private static let measuredBounds: ClosedRange<Double> = 60...300

    /// Speaking speeds people can actually picture, since "140 wpm" means
    /// nothing to most readers. Values are conventional: unhurried
    /// presentation, relaxed conversation, and a broadcast-style read.
    static let namedPaces: [(label: String, wpm: Double)] = [
        ("relaxed", 110),
        ("natural", 140),
        ("brisk", 165)
    ]

    /// The name for a speed — the nearest named pace, so a value nudged by
    /// the slider still reads as something rather than as a bare number.
    static func name(forWPM wpm: Double) -> String {
        namedPaces.min { abs($0.wpm - wpm) < abs($1.wpm - wpm) }?.label ?? "natural"
    }

    /// How long `count` words takes at `wpm`.
    static func seconds(forWords count: Int, wpm: Double) -> Double {
        guard count > 0, wpm > 0 else { return 0 }
        return Double(count) / wpm * 60
    }

    /// The speaker's observed pace, or `nil` while there isn't enough of the
    /// take to judge from.
    static func measuredWPM(wordsRead: Int, elapsed: TimeInterval) -> Double? {
        guard wordsRead >= minMeasuredWords, elapsed >= minMeasuredSeconds else { return nil }
        let raw = Double(wordsRead) / elapsed * 60
        return min(max(raw, measuredBounds.lowerBound), measuredBounds.upperBound)
    }

    /// The pace to estimate with: the speaker's own once it's trustworthy,
    /// otherwise the configured target.
    static func effectiveWPM(baseline: Double, wordsRead: Int, elapsed: TimeInterval) -> Double {
        measuredWPM(wordsRead: wordsRead, elapsed: elapsed) ?? baseline
    }

    /// "1:45", or "1:02:30" once a take passes an hour.
    static func timeString(_ seconds: Double) -> String {
        let total = Int((seconds.isFinite ? max(0, seconds) : 0).rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// Elapsed speaking time that excludes the stretches where the prompter was
/// paused, so the measured pace reflects time actually spent talking.
struct SpeakingClock {
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?

    var isRunning: Bool { startedAt != nil }

    mutating func start(at now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    mutating func pause(at now: Date) {
        guard let started = startedAt else { return }
        accumulated += max(0, now.timeIntervalSince(started))
        startedAt = nil
    }

    mutating func reset() {
        accumulated = 0
        startedAt = nil
    }

    func elapsed(at now: Date) -> TimeInterval {
        guard let started = startedAt else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(started))
    }
}

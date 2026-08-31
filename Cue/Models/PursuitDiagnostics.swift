import CoreGraphics
import Foundation

/// A once-a-second summary of what the scroll pursuit is actually doing.
///
/// Built to settle one question that cannot be answered by reading the code:
/// how often the catch-up **ceiling** is the binding constraint during a real
/// take, and whether `effectiveWPM` drifts away from the configured pace as
/// the take runs.
///
/// Why it exists: `ScrollPursuit.speed` takes the smaller of a term
/// proportional to the gap and a ceiling of `maxCatchUp x` the speaking pace.
/// The ceiling was meant to catch outliers. The arithmetic says it binds past
/// a gap of `response * maxCatchUp * wpm/60` words — under two at the default
/// pace — but arithmetic assumes a pace, and the pace is measured, so only a
/// real take can say.
///
/// **DEBUG only, and deliberately not `@Published`.** It is called from
/// `tick()`, so it must cost nothing per frame: it accumulates into scalars
/// and prints at most once a second. A print per frame would both flood the
/// console and add main-thread work to the very loop being measured.
#if DEBUG
struct PursuitDiagnostics {
    private var frames = 0
    private var ceilingBoundFrames = 0
    private var maxGap: CGFloat = 0
    private var lastLineHeight: CGFloat = 0
    private var lastEmit: Date?

    /// Records one frame. The proportional term and the ceiling are the two
    /// candidates `ScrollPursuit.speed` chooses between, recomputed here
    /// rather than returned from it — keeping the pure type free of
    /// diagnostic plumbing.
    ///
    /// `lineHeight` is printed so a device log can be checked against the
    /// script's actual row pitch: if the derived value and the spacing
    /// between rows on screen disagree, the ceiling is wrong.
    mutating func record(
        now: Date,
        gap: CGFloat,
        lineHeight: CGFloat,
        maxLinesPerSecond: CGFloat,
        response: CGFloat
    ) {
        frames += 1
        maxGap = max(maxGap, abs(gap))
        let proportional = abs(gap) / max(response, 0.001)
        let ceiling = lineHeight * maxLinesPerSecond
        if ceiling > 0, ceiling < proportional { ceilingBoundFrames += 1 }
        lastLineHeight = lineHeight

        guard let last = lastEmit else { lastEmit = now; return }
        guard now.timeIntervalSince(last) >= 1 else { return }
        lastEmit = now

        let bound = frames > 0 ? 100 * Double(ceilingBoundFrames) / Double(frames) : 0
        let gapLines = lastLineHeight > 0 ? maxGap / lastLineHeight : 0
        print(String(
            format: "[pursuit] ceiling-bound %3.0f%% of %d frames | maxGap %5.1fpt (%.1f lines) | lineHeight %5.1fpt | ceiling %.1f lines/s",
            bound, frames, maxGap, gapLines, lastLineHeight, Double(maxLinesPerSecond)
        ))
        frames = 0
        ceilingBoundFrames = 0
        maxGap = 0
    }
}
#endif

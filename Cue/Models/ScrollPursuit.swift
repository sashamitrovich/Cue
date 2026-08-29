import CoreGraphics
import Foundation

/// How the script travels toward the reading cursor.
///
/// Speech recognition does not arrive a word at a time. `SFSpeechRecognizer`
/// reports partial results every few hundred milliseconds, and each one can
/// match several words at once, so the cursor advances in bursts. Setting the
/// scroll target straight to the newly recognised word therefore asked the
/// script to cover a couple of seconds of speech in a fraction of a second
/// and then hold still until the next result — read as a stall followed by a
/// jump.
///
/// Instead the target travels at the pace the words are being spoken, which
/// turns the same bursts into continuous motion. Two properties matter and
/// are covered by the tests:
///
/// - It never overshoots: arriving at the cursor, it stops. No new words
///   means no new target, which means the script does not move at all while
///   the reader is silent.
/// - Deliberate cursor moves — a restart, a drag, a voice command — are not
///   paced. Walking the length of a script at speaking pace would take as
///   long as reading it.
enum ScrollPursuit {

    /// Points per second the target may travel, given how far behind it is.
    ///
    /// Proportional, not a flat multiple of the speaking pace. A flat
    /// multiple sounds reasonable and is wrong: at 1.3x the gap only closes
    /// at 0.3x pace, so a deficit of a few words takes tens of words to
    /// recover while the recogniser's own latency keeps re-opening it. The
    /// result is a *steady-state* offset — the active word sits permanently
    /// below the reading line and the reader's eyes track down the screen to
    /// follow it, which defeats the point of a reading line.
    ///
    /// So the speed scales with the gap: gentle when it is nearly there,
    /// quick when it is behind. The ceiling is what keeps that from becoming
    /// the teleport this type exists to prevent — bursts are still spread
    /// over a few hundred milliseconds rather than covered instantly.
    ///
    /// - Parameters:
    ///   - gap: how far the target still has to travel.
    ///   - pointsPerWord: how far the script moves per spoken word, measured
    ///     locally from the current layout so it reflects the reader's font
    ///     size and the current line wrapping.
    ///   - wordsPerMinute: the reader's measured pace, or their target pace
    ///     before enough of the take has been read to measure one.
    ///   - response: seconds the gap would take to close if nothing capped
    ///     it.
    ///   - maxCatchUp: ceiling, as a multiple of the speaking pace. Must be
    ///     comfortably above 1 or the steady-state offset comes back: the
    ///     gap closes at `(maxCatchUp - 1)x` pace once this is the binding
    ///     constraint.
    ///   - minimum: floor, for the opening words of a take when the per-word
    ///     estimate is still degenerate. `step` never overshoots, so a floor
    ///     cannot make the target sail past the cursor.
    static func speed(
        gap: CGFloat,
        pointsPerWord: CGFloat,
        wordsPerMinute: Double,
        response: CGFloat,
        maxCatchUp: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        let proportional = abs(gap) / max(response, 0.001)
        guard pointsPerWord > 0, wordsPerMinute > 0 else {
            return max(minimum, proportional)
        }
        let pace = pointsPerWord * CGFloat(wordsPerMinute / 60)
        return max(minimum, min(proportional, pace * maxCatchUp))
    }

    /// The target's next position.
    ///
    /// - Parameters:
    ///   - target: where the target is now.
    ///   - want: where the cursor says it should be.
    ///   - speed: points per second, from `speed(pointsPerWord:...)`.
    ///   - dt: seconds since the previous step.
    ///   - snapDistance: past this the cursor did not advance, it was moved;
    ///     pacing would take tens of seconds, so go directly.
    ///   - jumped: the caller knows this was a deliberate move.
    static func step(
        target: CGFloat,
        toward want: CGFloat,
        speed: CGFloat,
        dt: Double,
        snapDistance: CGFloat,
        jumped: Bool
    ) -> CGFloat {
        let delta = want - target
        if jumped || abs(delta) > snapDistance { return want }
        // Below half a point there is nothing to see and nothing to write.
        guard abs(delta) > 0.5 else { return target }
        // Never overshoot: the remaining distance is its own cap, which is
        // what makes arrival final rather than oscillating around the cursor.
        let step = min(abs(delta), speed * CGFloat(max(0, dt)))
        return target + (delta < 0 ? -step : step)
    }
}

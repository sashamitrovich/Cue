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
/// Instead the target travels toward the cursor at a bounded speed, which
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
    /// Proportional, not a flat multiple of anything. A flat multiple sounds
    /// reasonable and is wrong: at 1.3x the gap only closes at 0.3x pace, so
    /// a deficit of a few words takes tens of words to recover while the
    /// recogniser's own latency keeps re-opening it. The result is a
    /// *steady-state* offset — the active word sits permanently below the
    /// reading line and the reader's eyes track down the screen to follow it,
    /// which defeats the point of a reading line.
    ///
    /// So the speed scales with the gap, and the ceiling only stops that
    /// becoming the teleport this type exists to prevent.
    ///
    /// **The ceiling is measured in lines per second, deliberately.** It used
    /// to be a multiple of the speaking pace, `pointsPerWord * wpm/60`, and
    /// both of those were measured and unstable: the pace came from a
    /// whole-take average that collapses during a pause and lags a change of
    /// speed, and `pointsPerWord` was really counting line breaks inside a
    /// lookahead window, so it quantised and swung about fourfold with where
    /// the text happened to wrap. Between them the speed limit ranged from
    /// 1.2 to 4.7 lines a second on one device during one take.
    ///
    /// What the ceiling is actually protecting is the reader's eye — how much
    /// text may sweep past before they lose their place — and that is a
    /// perceptual limit with nothing to do with words per minute. A line is
    /// also the unit the eye tracks in. So the ceiling is a number of lines a
    /// second, and the only measured input is the line height, which is
    /// stable because it comes from the type size rather than from the text.
    ///
    /// - Parameters:
    ///   - gap: how far the target still has to travel.
    ///   - lineHeight: the script's row pitch, measured from the current
    ///     layout so it follows the reader's type size.
    ///   - maxLinesPerSecond: ceiling, in lines of script a second.
    ///   - response: seconds the gap would take to close if nothing capped
    ///     it.
    ///   - minimum: floor, for the opening frames of a take before the layout
    ///     has been measured. `step` never overshoots, so a floor cannot make
    ///     the target sail past the cursor.
    static func speed(
        gap: CGFloat,
        lineHeight: CGFloat,
        maxLinesPerSecond: CGFloat,
        response: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        let proportional = abs(gap) / max(response, 0.001)
        guard lineHeight > 0, maxLinesPerSecond > 0 else {
            return max(minimum, proportional)
        }
        return max(minimum, min(proportional, lineHeight * maxLinesPerSecond))
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

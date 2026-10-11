import Foundation

/// The pre-roll countdown's arithmetic (#26).
enum PreRoll {
    /// Whole seconds left to show, never below 1 while the countdown runs.
    ///
    /// A 3-second pre-roll must show 3 first, not 4: the deadline and the
    /// moment it starts have to come from one clock read, or the few
    /// microseconds between two reads round up to an extra second.
    static func remaining(until deadline: Date, at now: Date) -> Int {
        max(1, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }
}

import SwiftUI

/// The chrome's typeface.
///
/// The script keeps SF Pro at its natural width, and should: it is drawn for
/// legibility at a glance, which is exactly the peripheral-reading task this
/// app exists for. Everything around it — status, timing, button captions,
/// readouts — moves to a condensed face, uppercase and tracked out where the
/// label is small, the way lettering is set on the body of a camera. Before
/// this, one family did every job by default rather than by decision.
///
/// Condensed *system* widths rather than a bundled face, deliberately. iOS 16
/// gives this for free; the visual direction names Saira Condensed, which costs
/// app size and a `UIAppFonts` entry and should only be paid for if the system
/// width demonstrably fails to carry the look on a device. This enum is the one
/// place that swap would happen.
enum ChromeType {

    /// Small labels — button captions, eyebrows. Uppercase, tracked out.
    static func label(_ size: CGFloat = 11, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Tracking for `label`, in points. The direction sets 0.13em, and SwiftUI
    /// wants points, so it is resolved against the size it is used at.
    static func labelTracking(_ size: CGFloat = 11) -> CGFloat { size * 0.13 }

    /// Sentence-case chrome: the status line, banners, notices. Not uppercased
    /// — these are sentences, and setting a sentence in caps shouts.
    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// The pre-roll numeral. Light and condensed, with tabular figures so the
    /// count does not shift as it steps down.
    static func leader(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light).width(.condensed).monospacedDigit()
    }

    /// Live values — elapsed, remaining, pace, the recording clock. Monospaced
    /// digits so the numbers do not jitter as they count.
    static func readout(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }
}

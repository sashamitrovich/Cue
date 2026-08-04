import CoreGraphics

/// How far the script sits from each side of the screen.
///
/// The reader's margin is added on top of whatever the safe area requires,
/// rather than competing with it. Treating it as a floor instead made the
/// control appear dead in landscape, where the safe-area inset is ~47pt a
/// side and swallowed most of the slider's range.
///
/// The safe area is still honoured underneath, so the script can never be
/// pushed under a notch, and a small gap applies on edges that have no cutout
/// so text is never flush against the glass.
enum ScriptMargins {
    /// Extra margin the reader can add, in points, beyond what the screen needs.
    static let range: ClosedRange<CGFloat> = 0...80
    static let `default`: CGFloat = 8
    /// Breathing room on an edge with no cutout of its own.
    static let minimumGap: CGFloat = 8

    /// Padding for one side of the script.
    ///
    /// - Parameters:
    ///   - safeArea: the safe-area inset on that side.
    ///   - margin: the extra margin the reader chose.
    ///   - rail: width of the landscape control rail if it is on this side, else 0.
    static func inset(safeArea: CGFloat, margin: CGFloat, rail: CGFloat = 0) -> CGFloat {
        max(max(safeArea, minimumGap), 0) + max(margin, 0) + max(rail, 0)
    }
}

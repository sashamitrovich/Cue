import CoreGraphics

/// How far the script sits from each side of the screen.
///
/// The chosen margin acts as a *floor*, not an addition: where the safe-area
/// inset is larger — the notch side in landscape — that wins, because content
/// cannot be drawn under a cutout however narrow the margins are set. Adding
/// the two instead is what once cost the script ~73pt a side.
enum ScriptMargins {
    /// The narrowest and widest the margin control offers, in points.
    static let range: ClosedRange<CGFloat> = 8...96
    static let `default`: CGFloat = 16

    /// Padding for one side of the script.
    ///
    /// - Parameters:
    ///   - safeArea: the safe-area inset on that side.
    ///   - margin: the margin the reader chose.
    ///   - rail: width of the landscape control rail if it is on this side, else 0.
    static func inset(safeArea: CGFloat, margin: CGFloat, rail: CGFloat = 0) -> CGFloat {
        max(max(safeArea, margin), 0) + max(rail, 0)
    }
}

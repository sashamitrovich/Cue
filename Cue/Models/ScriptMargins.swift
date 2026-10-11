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
    /// The slider is a share of the room there is to give, not a point value.
    /// At its maximum the script narrows to `targetColumn`; every step in
    /// between moves the text by the same fraction of that room. As points
    /// (0-80) the maximum barely moved the text on a wide Mac window (#24);
    /// as a share of the width clamped to a fixed narrowest column, the slider
    /// went dead part-way on an upright iPhone at large fonts.
    static let narrowestShare: CGFloat = 0.30
    static let widestShare: CGFloat = 0.55
    /// The column at the maximum is never narrower than this, or than
    /// `columnPerPoint` times the font size, so a long word still fits on a
    /// line — unless that would leave no room to narrow at all.
    static let minimumColumn: CGFloat = 200
    static let columnPerPoint: CGFloat = 6

    /// Width of the script column with the slider at its maximum.
    static func targetColumn(width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let wanted = max(minimumColumn, fontSize * columnPerPoint)
        return max(narrowestShare * width, min(wanted, widestShare * width))
    }

    /// Padding for one side of the script.
    ///
    /// - Parameters:
    ///   - safeArea: the safe-area inset on that side.
    ///   - margin: the extra margin the reader chose, within `range`.
    ///   - rail: width of the landscape control rail if it is on this side, else 0.
    ///   - width: the full width the script is laid out in. 0 means unknown:
    ///     the margin is then taken as points.
    ///   - fontSize: the script's font size, which widens the narrowest column.
    static func inset(safeArea: CGFloat, margin: CGFloat, rail: CGFloat = 0,
                      width: CGFloat = 0, fontSize: CGFloat = 0) -> CGFloat {
        let fixed = max(max(safeArea, minimumGap), 0) + max(rail, 0)
        let chosen = min(max(margin, 0), range.upperBound)
        guard width > 0 else { return fixed + chosen }
        let room = max(0, (width - targetColumn(width: width, fontSize: fontSize)) / 2 - fixed)
        return fixed + chosen / range.upperBound * room
    }

    /// The slider's label: the share of the available room in use.
    static func percent(_ margin: CGFloat) -> Int {
        Int((min(max(margin, 0), range.upperBound) / range.upperBound * 100).rounded())
    }
}

import SwiftUI

/// Wraps words left-to-right like text, so individual word views can each
/// carry their own color state (spoken / active / upcoming).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6
    var alignment: ScriptAlignment = .leading

    /// One wrapped row: which subview indices it holds, their natural
    /// (unstretched) width, and the tallest word in it.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if current.width + size.width > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.indices.append(index)
            current.width += size.width + (current.indices.count > 1 ? spacing : 0)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let computed = rows(for: subviews, maxWidth: maxWidth)
        let totalHeight = computed.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, computed.count - 1))
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let computed = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for (rowIndex, row) in computed.enumerated() {
            let isLastRow = rowIndex == computed.count - 1
            // Print convention: a justified block's final row reads as
            // ordinary leading text rather than being stretched thin.
            let effectiveAlignment: ScriptAlignment = (alignment == .justified && isLastRow) ? .leading : alignment
            place(row: row, subviews: subviews, y: y, bounds: bounds, alignment: effectiveAlignment)
            y += row.height + lineSpacing
        }
    }

    private func place(row: Row, subviews: Subviews, y: CGFloat, bounds: CGRect, alignment: ScriptAlignment) {
        let sizes = row.indices.map { subviews[$0].sizeThatFits(.unspecified) }
        let gap: CGFloat
        let startX: CGFloat
        switch alignment {
        case .leading:
            gap = spacing
            startX = bounds.minX
        case .trailing:
            gap = spacing
            startX = bounds.maxX - row.width
        case .center:
            gap = spacing
            startX = bounds.minX + (bounds.width - row.width) / 2
        case .justified:
            let wordsWidth = sizes.reduce(0) { $0 + $1.width }
            let gaps = row.indices.count - 1
            gap = gaps > 0 ? (bounds.width - wordsWidth) / CGFloat(gaps) : spacing
            startX = bounds.minX
        }
        var x = startX
        for (offset, index) in row.indices.enumerated() {
            let size = sizes[offset]
            subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + gap
        }
    }
}

/// Collects each word's on-screen frame (in the "flow" named coordinate
/// space) so the prompter can compute how far to scroll to bring the active
/// word to the cue line.
struct WordFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

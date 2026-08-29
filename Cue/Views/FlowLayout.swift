import SwiftUI

/// Wraps words left-to-right like text, so individual word views can each
/// carry their own color state (spoken / active / upcoming).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6
    var alignment: ScriptAlignment = .leading
    /// Only here to invalidate the measurement cache. A word's width is pinned
    /// at its bold rendering for a given size (see `ScrollFlow.boldWidth`), so
    /// the measurements below survive a word changing state and only go stale
    /// when the reader changes the text size.
    var fontSize: CGFloat = 0

    /// One wrapped row: which subview indices it holds, their natural
    /// (unstretched) width, and the tallest word in it.
    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Measured sizes and the row breaks derived from them.
    ///
    /// Without this the script was measured three times over per layout pass —
    /// once in `sizeThatFits`, again in `placeSubviews`, and a third time per
    /// row inside `place` — for every word in the script, on every pass. The
    /// `Layout` protocol offers this cache precisely for that, and it was
    /// declared as `inout ()` and never used.
    struct Cache {
        var maxWidth: CGFloat = -1
        var fontSize: CGFloat = -1
        var sizes: [CGSize] = []
        var rows: [Row] = []
        var totalHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    /// Subviews changed identity or count — throw the measurements away.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.maxWidth = -1
    }

    /// Measures and wraps, reusing the previous result when nothing that
    /// affects it has changed.
    private func resolve(_ cache: inout Cache, subviews: Subviews, maxWidth: CGFloat) {
        guard cache.maxWidth != maxWidth
                || cache.fontSize != fontSize
                || cache.sizes.count != subviews.count else { return }

        var sizes: [CGSize] = []
        sizes.reserveCapacity(subviews.count)
        for subview in subviews { sizes.append(subview.sizeThatFits(.unspecified)) }

        var rows: [Row] = []
        var current = Row()
        for (index, size) in sizes.enumerated() {
            if current.width + size.width > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.indices.append(index)
            current.width += size.width + (current.indices.count > 1 ? spacing : 0)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }

        cache.maxWidth = maxWidth
        cache.fontSize = fontSize
        cache.sizes = sizes
        cache.rows = rows
        cache.totalHeight = rows.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        resolve(&cache, subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: maxWidth, height: cache.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        resolve(&cache, subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for (rowIndex, row) in cache.rows.enumerated() {
            let isLastRow = rowIndex == cache.rows.count - 1
            // Print convention: a justified block's final row reads as
            // ordinary leading text rather than being stretched thin.
            let effectiveAlignment: ScriptAlignment = (alignment == .justified && isLastRow) ? .leading : alignment
            place(row: row, sizes: cache.sizes, subviews: subviews, y: y, bounds: bounds, alignment: effectiveAlignment)
            y += row.height + lineSpacing
        }
    }

    private func place(row: Row, sizes allSizes: [CGSize], subviews: Subviews, y: CGFloat, bounds: CGRect, alignment: ScriptAlignment) {
        let sizes = row.indices.map { allSizes[$0] }
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

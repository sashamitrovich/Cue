import CoreGraphics

/// Rows of words as they are actually drawn.
///
/// "Go back a line" means the line you can see, not the line you typed. The
/// script's paragraphs wrap into many rows on screen, so stepping by typed
/// line jumps a whole paragraph — which is what the first version did.
///
/// Only the measured word frames know where the rows fall, so that is what
/// this works from.
enum VisualLines {
    /// Groups word ids into rows, top to bottom, by their vertical position.
    ///
    /// - Parameter tolerance: how far apart two words' centres can be and
    ///   still count as the same row. Descenders and mixed sizes mean rows are
    ///   not perfectly level, so this is a fraction of the line height rather
    ///   than an exact match.
    static func rows(from frames: [Int: CGRect], tolerance: CGFloat = 12) -> [[Int]] {
        guard !frames.isEmpty else { return [] }
        let sorted = frames.sorted { lhs, rhs in
            if abs(lhs.value.midY - rhs.value.midY) > tolerance { return lhs.value.midY < rhs.value.midY }
            return lhs.key < rhs.key           // reading order within a row
        }

        var rows: [[Int]] = []
        var current: [Int] = []
        var rowY: CGFloat = .greatestFiniteMagnitude
        for (id, frame) in sorted {
            if current.isEmpty || abs(frame.midY - rowY) <= tolerance {
                if current.isEmpty { rowY = frame.midY }
                current.append(id)
            } else {
                rows.append(current)
                current = [id]
                rowY = frame.midY
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// The word to put the cursor on when stepping `delta` rows from `index`.
    ///
    /// Returns the first word of the target row, so reading resumes at the
    /// start of a line rather than mid-phrase. Clamped at both ends, and nil
    /// when there is nothing measured to work from — the caller then leaves
    /// the cursor alone rather than guessing.
    static func wordStepping(_ delta: Int, from index: Int, frames: [Int: CGRect], tolerance: CGFloat = 12) -> Int? {
        let rows = rows(from: frames, tolerance: tolerance)
        guard !rows.isEmpty else { return nil }
        guard let currentRow = rows.firstIndex(where: { $0.contains(index) })
                ?? rows.lastIndex(where: { ($0.first ?? 0) <= index }) else { return nil }
        let target = min(max(currentRow + delta, 0), rows.count - 1)
        return rows[target].first
    }

    /// The first word of whichever row sits closest to `flowY` — the row a
    /// manually-scrolled reading line is now pointing at. Used to pick up
    /// tracking from wherever the user dragged to, rather than from
    /// wherever it was left before they went manual.
    static func nearestRowStart(toFlowY flowY: CGFloat, frames: [Int: CGRect], tolerance: CGFloat = 12) -> Int? {
        let grouped = rows(from: frames, tolerance: tolerance)
        guard !grouped.isEmpty else { return nil }
        func rowMidY(_ row: [Int]) -> CGFloat {
            let ys = row.compactMap { frames[$0]?.midY }
            return ys.reduce(0, +) / CGFloat(max(ys.count, 1))
        }
        let closest = grouped.min { abs(rowMidY($0) - flowY) < abs(rowMidY($1) - flowY) }
        return closest?.first
    }
}

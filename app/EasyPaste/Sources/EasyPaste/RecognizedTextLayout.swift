import Foundation

/// Vision's observation order is not a reading order: a small badge can be
/// returned before its neighbouring date. Work in image pixels (origin below)
/// to restore rows, indentation and paragraph gaps without inventing any text.
enum RecognizedTextLayout {
    struct Fragment {
        let text: String
        let bounds: CGRect
    }
    private struct Row {
        var fragments: [Fragment]
        var center: CGFloat { median(fragments.map { $0.bounds.midY }) }
        var height: CGFloat { median(fragments.map { $0.bounds.height }) }
        var bounds: CGRect { fragments.dropFirst().reduce(fragments[0].bounds) { $0.union($1.bounds) } }
        func match(_ fragment: Fragment) -> CGFloat? {
            // Compare to the row's typical text, not the union of its bounds:
            // a large title must not bridge two otherwise distinct body lines.
            let height = self.height, other = fragment.bounds
            let distance = abs(center - other.midY)
            let overlap = min(center + height / 2, other.maxY) - max(center - height / 2, other.minY)
            guard overlap >= min(height, other.height) * 0.45,
                  distance <= max(height, other.height) * 0.65 else { return nil }
            return overlap / min(height, other.height) - distance / max(height, other.height)
        }
    }
    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
    static func render(_ fragments: [Fragment]) -> String {
        let ordered = fragments.compactMap { fragment -> Fragment? in
            let text = fragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = fragment.bounds
            guard !text.isEmpty, b.minX.isFinite, b.minY.isFinite, b.maxX.isFinite, b.maxY.isFinite,
                  b.width.isFinite, b.height.isFinite,
                  b.width > 0, b.height > 0 else { return nil }
            return Fragment(text: text, bounds: b)
        }.sorted {
            if $0.bounds.midY != $1.bounds.midY { return $0.bounds.midY > $1.bounds.midY }
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            return $0.text < $1.text
        }
        guard !ordered.isEmpty else { return "" }
        var rows: [Row] = []
        for fragment in ordered {
            var match: (index: Int, score: CGFloat)?
            for index in rows.indices.reversed() {
                let row = rows[index]
                if row.center - fragment.bounds.midY > max(row.height, fragment.bounds.height) * 2 { break }
                if let score = row.match(fragment), score > (match?.score ?? -.infinity) { match = (index, score) }
            }
            if let match { rows[match.index].fragments.append(fragment) }
            else { rows.append(Row(fragments: [fragment])) }
        }
        rows.sort { $0.center > $1.center }
        let height = median(rows.map(\.height))
        let gaps = zip(rows, rows.dropFirst()).map { max(0, $0.bounds.minY - $1.bounds.maxY) }.sorted()
        // Learn ordinary line spacing from the closer half of the rows. Cap
        // the threshold so two widely separated single lines remain two blocks.
        let ordinaryGap = median(Array(gaps.prefix(max(1, (gaps.count + 1) / 2))))
        let paragraphGap = max(height, min(ordinaryGap * 1.8, height * 2))
        let left = ordered.map { $0.bounds.minX }.min() ?? 0
        var output = ""
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let gap = rows[index - 1].bounds.minY - row.bounds.maxY
                output += gap > paragraphGap ? "\n\n" : "\n"
            }
            let cells = row.fragments.sorted { $0.bounds.minX < $1.bounds.minX }
            let indent = cells[0].bounds.minX - left
            if indent >= height * 1.2 {
                output += String(repeating: " ", count: Int(min(24, (indent / max(1, height * 0.45)).rounded())))
            }
            for (cellIndex, cell) in cells.enumerated() {
                if cellIndex > 0 {
                    let gap = cell.bounds.minX - cells[cellIndex - 1].bounds.maxX
                    // Separate visibly distant columns using ordinary text characters.
                    output += gap >= row.height * 2 ? " | " : " "
                }
                output += cell.text
            }
        }
        return output
    }
}

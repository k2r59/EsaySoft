import Foundation

/// Vision's observation order is not a reading order: a small badge can be
/// returned before its neighbouring date. Work in image pixels (origin below)
/// to restore rows, indentation and paragraph gaps without inventing any text.
enum RecognizedTextLayout {
    struct Document {
        let text: String
        let html: String?
    }
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
        document(fragments, includeHTML: false).text
    }
    static func document(_ fragments: [Fragment], includeHTML: Bool = true) -> Document {
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
        guard !ordered.isEmpty else { return Document(text: "", html: includeHTML ? html(forText: "") : nil) }
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
                    output += gap >= row.height * 2 ? "\t" : " "
                }
                output += cell.text
            }
        }
        return Document(text: output, html: includeHTML ? html(rows: rows, paragraphGap: paragraphGap, height: height, text: output) : nil)
    }
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    private static func envelope(_ body: String) -> String {
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body><!--StartFragment-->" + body + "<!--EndFragment--></body></html>"
    }
    static func html(forText text: String) -> String {
        envelope("<pre style=\"white-space:pre-wrap;font-family:monospace;font-size:14px\">" + escaped(text) + "</pre>")
    }
    private static func html(rows: [Row], paragraphGap: CGFloat, height: CGFloat, text: String) -> String {
        // A shared grid keeps small labels and indentation in their observed
        // columns. Unlike CSS positioning, tables survive rich clipboard paste
        // in document editors. No original HTML, links or scripts are inferred.
        var columns: [CGFloat] = []
        for x in rows.flatMap({ $0.fragments.map { $0.bounds.minX } }).sorted() {
            if columns.last.map({ x - $0 > height * 0.75 }) ?? true { columns.append(x) }
        }
        guard !columns.isEmpty, columns.count <= 64 else { return html(forText: text) }
        let right = rows.map { $0.bounds.maxX }.max() ?? columns.last!
        let scale = 14 / max(1, height)
        var markup = "<table role=\"presentation\" cellspacing=\"0\" cellpadding=\"0\" style=\"border-collapse:collapse;font-family:Arial,sans-serif;font-size:14px;line-height:1.4\"><colgroup>"
        for index in columns.indices {
            let end = index + 1 < columns.count ? columns[index + 1] : right
            let width = Int(min(1200, max(1, ((end - columns[index]) * scale).rounded())))
            markup += "<col width=\"\(width)\" style=\"width:\(width)px\">"
        }
        markup += "</colgroup><tbody>"
        for (index, row) in rows.enumerated() {
            if index > 0, rows[index - 1].bounds.minY - row.bounds.maxY > paragraphGap {
                markup += "<tr><td colspan=\"\(columns.count)\" style=\"height:14px;line-height:14px\">&#160;</td></tr>"
            }
            var cells: [(column: Int, text: String)] = []
            for fragment in row.fragments.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
                let column = columns.indices.min { abs(columns[$0] - fragment.bounds.minX) < abs(columns[$1] - fragment.bounds.minX) }!
                if cells.last?.column == column { cells[cells.count - 1].text += " " + fragment.text }
                else { cells.append((column, fragment.text)) }
            }
            markup += "<tr>"
            if let first = cells.first, first.column > 0 { markup += "<td colspan=\"\(first.column)\"></td>" }
            for (cellIndex, cell) in cells.enumerated() {
                let end = cellIndex + 1 < cells.count ? cells[cellIndex + 1].column : columns.count
                markup += "<td colspan=\"\(max(1, end - cell.column))\" style=\"padding:0;vertical-align:baseline;white-space:pre-wrap\">\(escaped(cell.text))</td>"
            }
            markup += "</tr>"
        }
        return envelope(markup + "</tbody></table>")
    }
}

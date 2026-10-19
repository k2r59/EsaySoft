import Foundation

struct CSVDocument: Sendable {
    var rows: [[String]]
    let delimiter: UInt8
    let newline: String
    let trailingNewline: Bool
    let bom: Bool
    var columnCount: Int { rows.first?.count ?? 0 }

    static func parse(_ text: String, delimiter: UInt8?, sample: Bool = false) throws -> CSVDocument {
        if let delimiter { return try read(text, delimiter: delimiter, sample: sample) }
        var best: CSVDocument?
        var preferredError: Error?, preferredScore = 0
        let header = text.prefix { $0 != "\n" && $0 != "\r" }
        for delimiter: UInt8 in [44, 59, 9, 124] {
            try Task.checkCancellation()
            do {
                let candidate = try read(text, delimiter: delimiter, sample: sample)
                if candidate.columnCount > 1, best == nil || candidate.columnCount > best!.columnCount { best = candidate }
            } catch {
                let score = header.utf8.filter { $0 == delimiter }.count
                if score > preferredScore { preferredScore = score; preferredError = error }
            }
        }
        guard let best else {
            if let preferredError { throw preferredError }
            throw TextIssue(message: "Séparateur non reconnu. Choisis-le dans le menu CSV.")
        }
        return best
    }
    private static func read(_ text: String, delimiter: UInt8, sample: Bool) throws -> CSVDocument {
        guard !text.isEmpty else { throw TextIssue(message: "Aucune donnée CSV") }
        var scan = ByteScanner(text), rows: [[String]] = [], row: [String] = [], field: [UInt8] = []
        var quoted = false, closed = false, endedRow = false, cells = 0
        let bom = scan.bytes.starts(with: [0xEF, 0xBB, 0xBF])
        if bom { scan.position = 3 }
        func checkedRow(_ row: [String], at position: Int) throws {
            if let width = rows.first?.count, row.count != width { throw scan.issue("\(row.count) colonnes au lieu de \(width)", at: position) }
        }
        func checkLimits() throws {
            guard row.count <= 256, cells <= 200_000 else { throw TextIssue(message: "Tableau limité à 256 colonnes et 200 000 cellules.") }
        }
        var firstNewline: String?
        while let c = scan.current {
            try scan.checkpoint(); scan.position += 1; endedRow = false
            if quoted {
                if c == 34 {
                    if scan.current == 34 { field.append(34); scan.position += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == delimiter || c == 10 || c == 13 {
                row.append(String(decoding: field, as: UTF8.self)); cells += 1; field.removeAll(keepingCapacity: true); closed = false
                try checkLimits()
                if c != delimiter {
                    var newline = c == 13 ? "\r" : "\n"
                    if c == 13, scan.current == 10 { scan.position += 1; newline = "\r\n" }
                    if firstNewline == nil { firstNewline = newline }
                    try checkedRow(row, at: scan.position); rows.append(row); row.removeAll(keepingCapacity: true); endedRow = true
                }
            } else if c == 34 {
                guard field.isEmpty, !closed else { throw scan.issue("Guillemet inattendu dans une cellule") }
                quoted = true
            } else {
                guard !closed else { throw scan.issue("Séparateur attendu après le guillemet") }
                field.append(c)
            }
        }
        // Detection uses only complete records from a bounded prefix.
        if !sample {
            guard !quoted else { throw scan.issue("Guillemet de fermeture manquant") }
            if !endedRow { row.append(String(decoding: field, as: UTF8.self)); cells += 1; try checkLimits(); try checkedRow(row, at: scan.position); rows.append(row) }
        }
        guard !rows.isEmpty else { throw TextIssue(message: "Aucune ligne CSV complète") }
        return CSVDocument(rows: rows, delimiter: delimiter, newline: firstNewline ?? "\n", trailingNewline: endedRow, bom: bom)
    }
    func serialized() throws -> String {
        let separator = String(UnicodeScalar(delimiter)), forbidden = CharacterSet(charactersIn: separator + "\"\r\n")
        var output = bom ? "\u{FEFF}" : ""
        for (index, row) in rows.enumerated() {
            try Task.checkCancellation()
            if index > 0 { output += newline }
            for (column, cell) in row.enumerated() {
                if column > 0 { output += separator }
                if cell.rangeOfCharacter(from: forbidden) != nil { output += "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                else { output += cell }
            }
            guard output.utf8.count <= StructuredText.outputLimit else { throw TextIssue(message: "Le résultat dépasse 8 Mo.") }
        }
        if trailingNewline { output += newline }
        return output
    }
}

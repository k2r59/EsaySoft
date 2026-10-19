import Foundation

/// A conservative SQL layout pass: preserve token spelling and every original
/// whitespace run except at clause boundaries, where indentation is introduced.
/// It is deliberately not a SQL validator or a query execution engine.
enum SQLTextFormatter {
    struct Token { let range: Range<Int>; let word: String; let depth: Int; let literal: Bool }
    static func format(_ text: String, dialect: SQLDialect) throws -> String {
        let bytes = Array(text.utf8), tokens = try lex(text, dialect: dialect)
        let clauses: Set<String> = ["SELECT", "FROM", "WHERE", "HAVING", "LIMIT", "OFFSET", "RETURNING", "VALUES", "SET", "UNION", "EXCEPT", "INTERSECT"]
        let joins: Set<String> = ["LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "NATURAL"]
        var output: [UInt8] = [], previous = 0
        for (index, token) in tokens.enumerated() {
            if index & 255 == 0 { try Task.checkCancellation() }
            let gap = bytes[previous..<token.range.lowerBound]
            let next = index + 1 < tokens.count ? tokens[index + 1].word : ""
            let last = index > 0 ? tokens[index - 1].word : ""
            let clause = clauses.contains(token.word) || ((token.word == "ORDER" || token.word == "GROUP") && next == "BY") || (joins.contains(token.word) && (next == "JOIN" || next == "OUTER")) || (token.word == "JOIN" && !joins.contains(last))
            // In SQL, a newline between adjacent string literals can be semantic.
            // Never normalize existing whitespace; literals/comments are opaque.
            if index > 0, token.depth == 0, clause, !gap.isEmpty, !gap.contains(10), !gap.contains(13), last != "." {
                output.append(10)
            } else { output.append(contentsOf: gap) }
            output.append(contentsOf: bytes[token.range]); previous = token.range.upperBound
        }
        output.append(contentsOf: bytes[previous...])
        guard output.count <= StructuredText.outputLimit else { throw TextIssue(message: "Le résultat dépasse 8 Mo.") }
        return String(decoding: output, as: UTF8.self)
    }
    static func lex(_ text: String, dialect: SQLDialect) throws -> [Token] {
        var scan = ByteScanner(text), result: [Token] = [], depth = 0
        func starts(_ value: [UInt8]) -> Bool { scan.bytes[scan.position...].starts(with: value) }
        func wordByte(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) || (48...57).contains(b) || b == 95 || b >= 128 }
        while let c = scan.current {
            try scan.checkpoint()
            if ByteScanner.isSpace(c) { try scan.space(); continue }
            let start = scan.position
            var literal = false
            if starts([45,45]) || (c == 35 && dialect == .mysql) {
                while let x = scan.current, x != 10, x != 13 { scan.position += 1; try scan.checkpoint() }; literal = true
            } else if starts([47,42]) {
                scan.position += 2; var nesting = 1
                while scan.current != nil, nesting > 0 {
                    try scan.checkpoint()
                    if starts([47,42]) { nesting += 1; scan.position += 2 }
                    else if starts([42,47]) { nesting -= 1; scan.position += 2 }
                    else { scan.position += 1 }
                }
                guard nesting == 0 else { throw scan.issue("Commentaire SQL non fermé") }; literal = true
            } else if c == 39 || c == 34 || c == 96 || c == 91 {
                let end: UInt8 = c == 91 ? 93 : c
                let backslash = dialect == .mysql || (dialect == .postgres && start > 0 && [69,101].contains(scan.bytes[start - 1]))
                scan.position += 1; var closed = false
                while let x = scan.current {
                    try scan.checkpoint(); scan.position += 1
                    if x == end {
                        if scan.current == end { scan.position += 1 } else { closed = true; break }
                    } else if x == 92, backslash, scan.current != nil { scan.position += 1 }
                }
                guard closed else { throw scan.issue("Guillemet ou crochet SQL non fermé") }; literal = true
            } else if c == 36, dialect == .postgres || dialect == .standard {
                var end = start + 1
                while end < scan.bytes.count, wordByte(scan.bytes[end]) { end += 1 }
                if end < scan.bytes.count, scan.bytes[end] == 36 {
                    let delimiter = Array(scan.bytes[start...end]); scan.position = end + 1
                    while scan.current != nil, !starts(delimiter) { scan.position += 1; try scan.checkpoint() }
                    guard scan.current != nil else { throw scan.issue("Bloc SQL $…$ non fermé") }
                    scan.position += delimiter.count; literal = true
                } else { scan.position += 1 }
            } else if wordByte(c) {
                while let x = scan.current, wordByte(x) { scan.position += 1; try scan.checkpoint() }
            } else {
                scan.position += 1
                if c == 40 { depth += 1; guard depth <= StructuredText.depthLimit else { throw scan.issue("Imbrication limitée à 128 niveaux") } }
                if c == 41 { depth -= 1; guard depth >= 0 else { throw scan.issue("Parenthèse SQL inattendue") } }
            }
            let range = start..<scan.position
            result.append(Token(range: range, word: literal ? "" : String(decoding: scan.bytes[range], as: UTF8.self).uppercased(), depth: depth, literal: literal))
            guard result.count <= 250_000 else { throw TextIssue(message: "Requête trop complexe pour cet aperçu.") }
        }
        guard depth == 0 else { throw scan.issue("Parenthèse SQL non fermée") }
        return result
    }
}

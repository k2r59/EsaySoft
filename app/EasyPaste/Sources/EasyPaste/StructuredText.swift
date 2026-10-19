import Foundation

enum StructuredFormat: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON", sql = "SQL", csv = "CSV", xml = "XML", markdown = "Markdown"
    var id: String { rawValue }
    var fileExtension: String { self == .markdown ? "md" : rawValue.lowercased() }
    var icon: String { self == .markdown ? "text.document" : self == .csv ? "tablecells" : "curlybraces" }
}
enum TextPresentation: String, CaseIterable, Identifiable, Sendable {
    case original = "Original", formatted = "Formaté", compact = "Compact", table = "Tableau", outline = "Structure", source = "Source", rendered = "Aperçu"
    var id: String { rawValue }
}
enum SQLDialect: String, CaseIterable, Identifiable, Sendable {
    case standard = "Standard", postgres = "PostgreSQL", mysql = "MySQL", sqlite = "SQLite", tsql = "SQL Server"
    var id: String { rawValue }
}
struct StructuredOptions: Equatable, Sendable {
    var delimiter: UInt8? = nil
    var dialect = SQLDialect.standard
}
struct TextIssue: LocalizedError, Equatable, Sendable {
    var message: String
    var line: Int? = nil
    var column: Int? = nil
    var errorDescription: String? {
        guard let line else { return message }
        return "\(message) · ligne \(line)" + (column.map { ", colonne \($0)" } ?? "")
    }
}
struct XMLBranch: Identifiable, Sendable {
    let id: Int
    var label: String
    var children: [XMLBranch] = []
}
struct StructuredResult: Sendable {
    var text: String
    var csv: CSVDocument? = nil
    var xml: [XMLBranch] = []
    var markdown: MarkdownDocument? = nil
    var note: String? = nil
}

enum StructuredText {
    static let inputLimit = 4 * 1024 * 1024
    static let outputLimit = 8 * 1024 * 1024
    static let previewLimit = 64 * 1024
    static let displayLimit = 128 * 1024
    static let depthLimit = 128

    /// A bounded hint, not validation. No full-document parsing on the UI thread.
    static func hint(_ text: String) -> StructuredFormat? {
        let sample = String(decoding: text.utf8.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        guard !sample.isEmpty else { return nil }
        if sample.hasPrefix("{") || (sample.hasPrefix("[") && !MarkdownDocument.hasStrongHint(sample)) { return .json }
        if sample.hasPrefix("<?xml") || sample.hasPrefix("<!DOCTYPE") || sample.hasPrefix("<!--") || sample.range(of: #"^<[A-Za-z_:][\w:.-]*(?:\s|>|/)"#, options: .regularExpression) != nil { return .xml }
        if sample.range(of: #"(?is)^(?:(?:--[^\r\n]*(?:\r?\n|\r))|(?:/\*.*?\*/)|\s)*(?:SELECT\s+.+\s+FROM\b|WITH\s+.+\s+AS\s*\(|INSERT\s+INTO\b|UPDATE\s+.+\s+SET\b|DELETE\s+FROM\b|CREATE\s+TABLE\b|ALTER\s+TABLE\b)"#, options: .regularExpression) != nil { return .sql }
        if MarkdownDocument.hasStrongHint(sample) { return .markdown }
        // Ordinary sentences containing commas should remain ordinary text.
        if sample.contains("\n") || sample.contains("\r"), let csv = try? CSVDocument.parse(sample, delimiter: nil, sample: text.utf8.count > 4096), csv.rows.count >= 2, csv.columnCount > 1 { return .csv }
        return nil
    }
    static func process(_ text: String, format: StructuredFormat, presentation: TextPresentation = .formatted, options: StructuredOptions = .init()) throws -> StructuredResult {
        try Task.checkCancellation()
        guard text.utf8.count <= inputLimit else { throw TextIssue(message: "Formatage limité à 4 Mo. L’original reste disponible.") }
        switch format {
        case .json:
            var parser = JSONTextFormatter(text, compact: presentation == .compact)
            return StructuredResult(text: try parser.run())
        case .csv:
            let csv = try CSVDocument.parse(text, delimiter: options.delimiter)
            return StructuredResult(text: text, csv: csv)
        case .sql: return StructuredResult(text: try SQLTextFormatter.format(text, dialect: options.dialect), note: "Mise en forme SQL ; syntaxe non validée.")
        case .xml: return try XMLTextFormatter.format(text)
        case .markdown:
            let document = try MarkdownDocument.parse(text)
            return StructuredResult(text: text, markdown: document, note: document.hasImages ? "Images : texte alternatif affiché, sans téléchargement." : "Markdown · rendu local")
        }
    }
    static func prefix(_ text: String, bytes: Int) -> String {
        // Drop incomplete UTF-8 at the boundary rather than show a replacement character.
        var data = Array(text.utf8.prefix(bytes))
        while !data.isEmpty {
            if let s = String(bytes: data, encoding: .utf8) { return s }
            data.removeLast()
        }
        return ""
    }
}

enum StructuredHintCache {
    private final class Entry: NSObject { let value: StructuredFormat?; init(_ value: StructuredFormat?) { self.value = value } }
    private static let cache: NSCache<NSString, Entry> = { let cache = NSCache<NSString, Entry>(); cache.countLimit = 2000; return cache }()
    static func hint(text: String, fingerprint: String) -> StructuredFormat? {
        guard !fingerprint.isEmpty else { return StructuredText.hint(text) }
        if let entry = cache.object(forKey: fingerprint as NSString) { return entry.value }
        let value = StructuredText.hint(text); cache.setObject(Entry(value), forKey: fingerprint as NSString); return value
    }
}

struct ByteScanner {
    let bytes: [UInt8]
    var position = 0
    init(_ text: String) { bytes = Array(text.utf8) }
    var current: UInt8? { position < bytes.count ? bytes[position] : nil }
    static func isSpace(_ c: UInt8) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
    mutating func space() throws {
        while let c = current, Self.isSpace(c) { position += 1; try checkpoint() }
    }
    func checkpoint() throws { if position & 4095 == 0 { try Task.checkCancellation() } }
    func issue(_ message: String, at offset: Int? = nil) -> TextIssue {
        let prefix = bytes.prefix(offset ?? position)
        let line = prefix.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        let start = prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0
        let column = String(decoding: prefix.dropFirst(start), as: UTF8.self).count + 1
        return TextIssue(message: message, line: line, column: column)
    }
}

/// Whitespace-only JSON transformation. Numeric lexemes, duplicate keys, escapes
/// and field ordering are never decoded/re-encoded through floating point values.
struct JSONTextFormatter {
    private var scan: ByteScanner
    private var output: [UInt8] = []
    private let compact: Bool
    init(_ text: String, compact: Bool) { scan = ByteScanner(text); self.compact = compact }
    mutating func run() throws -> String {
        if scan.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { scan.position = 3 }
        try scan.space(); try value(depth: 0); try scan.space()
        guard scan.current == nil else { throw scan.issue("Contenu inattendu après la valeur JSON") }
        return String(decoding: output, as: UTF8.self)
    }
    private mutating func put(_ b: UInt8) throws {
        guard output.count < StructuredText.outputLimit else { throw TextIssue(message: "Le résultat dépasse 8 Mo. Utilise la vue Original ou Compact.") }
        output.append(b)
    }
    private mutating func newline(_ depth: Int) throws {
        guard !compact else { return }; try put(10)
        for _ in 0..<(depth * 2) { try put(32) }
    }
    private mutating func value(depth: Int) throws {
        try Task.checkCancellation()
        guard depth <= StructuredText.depthLimit else { throw scan.issue("Imbrication limitée à 128 niveaux") }
        guard let c = scan.current else { throw scan.issue("Valeur JSON attendue") }
        if c == 123 || c == 91 {
            let object = c == 123, end: UInt8 = object ? 125 : 93
            try put(c); scan.position += 1; try scan.space()
            if scan.current == end { try put(end); scan.position += 1; return }
            try newline(depth + 1)
            while true {
                if object {
                    guard scan.current == 34 else { throw scan.issue("Clé entre guillemets attendue") }
                    try string(); try scan.space()
                    guard scan.current == 58 else { throw scan.issue("Deux-points attendu après la clé") }
                    try put(58); if !compact { try put(32) }; scan.position += 1; try scan.space()
                }
                try value(depth: depth + 1); try scan.space()
                if scan.current == end { try newline(depth); try put(end); scan.position += 1; return }
                guard scan.current == 44 else { throw scan.issue("Virgule ou \(object ? "accolade" : "crochet") de fermeture attendu") }
                try put(44); scan.position += 1; try scan.space(); try newline(depth + 1)
            }
        } else if c == 34 { try string() }
        else if c == 45 || (48...57).contains(c) { try number() }
        else {
            let literal = c == 116 ? "true" : c == 102 ? "false" : c == 110 ? "null" : ""
            guard !literal.isEmpty else { throw scan.issue("Valeur JSON invalide") }
            for b in literal.utf8 {
                guard scan.current == b else { throw scan.issue("Valeur JSON invalide") }
                try put(b); scan.position += 1
            }
        }
    }
    private mutating func string() throws {
        try put(34); scan.position += 1
        while let c = scan.current {
            try scan.checkpoint(); guard c >= 32 else { throw scan.issue("Caractère de contrôle dans une chaîne") }
            try put(c); scan.position += 1
            if c == 34 { return }
            if c == 92 {
                guard let escaped = scan.current, [34,92,47,98,102,110,114,116,117].contains(escaped) else { throw scan.issue("Échappement JSON invalide") }
                try put(escaped); scan.position += 1
                if escaped == 117 {
                    for _ in 0..<4 {
                        guard let h = scan.current, (48...57).contains(h) || (65...70).contains(h) || (97...102).contains(h) else { throw scan.issue("Quatre chiffres hexadécimaux attendus après \\u") }
                        try put(h); scan.position += 1
                    }
                }
            }
        }
        throw scan.issue("Guillemet de fermeture manquant")
    }
    private mutating func number() throws {
        if scan.current == 45 { try put(45); scan.position += 1 }
        guard let c = scan.current, (48...57).contains(c) else { throw scan.issue("Nombre JSON invalide") }
        if c == 48 { try put(c); scan.position += 1 }
        else { try digits() }
        if scan.current == 46 { try put(46); scan.position += 1; try digits(required: true) }
        if scan.current == 101 || scan.current == 69 {
            try put(scan.current!); scan.position += 1
            if scan.current == 43 || scan.current == 45 { try put(scan.current!); scan.position += 1 }
            try digits(required: true)
        }
    }
    private mutating func digits(required: Bool = false) throws {
        let start = scan.position
        while let c = scan.current, (48...57).contains(c) { try put(c); scan.position += 1; try scan.checkpoint() }
        if required && start == scan.position { throw scan.issue("Chiffre attendu") }
    }
}

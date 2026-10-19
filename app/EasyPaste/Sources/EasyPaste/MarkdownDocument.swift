import Foundation

/// Foundation parses CommonMark/GFM semantics. The source is never reserialized.
/// Only a bounded preview is parsed; copies and exports retain the complete source.
struct MarkdownDocument: Sendable {
    struct Span: Sendable {
        var range: NSRange
        var bold = false, italic = false, code = false, strike = false, image = false
        var link: URL?
    }
    struct Cell: Sendable {
        var tableID: Int, row: Int, column: Int, columns: Int
        var header: Bool
        var alignment: PresentationIntent.TableColumn.Alignment
    }
    struct Block: Sendable {
        var range = NSRange(location: 0, length: 0)
        var heading = 0, listDepth = 0, quoteDepth = 0
        var code = false, rule = false
        var cell: Cell?
    }
    var text: String
    var spans: [Span]
    var blocks: [Block]
    var truncated: Bool
    var hasImages: Bool
    static let blockLimit = 1000
    static let spanLimit = 4000
    static let columnLimit = 32

    private static let hints: [NSRegularExpression] = [
        #"(?m)^ {0,3}(?:#{1,6}[ \t]+\S|`{3,}|~{3,}|>[ \t]+\S)"#,
        #"(?m)^.+\r?\n {0,3}(?:={3,}|-{3,})[ \t]*(?:\r?$)"#,
        #"(?m)^ {0,3}(?:[-+*]|[0-9]{1,9}[.)])[ \t]+[^\r\n]+\r?\n {0,3}(?:[-+*]|[0-9]{1,9}[.)])[ \t]+"#,
        #"\[[^\]\r\n]+\]\([^\)\r\n]+\)|\*\*[^*\r\n]+\*\*|__[^_\r\n]+__"#,
        #"(?m)^\|? *:?-{3,}:? *(?:\| *:?-{3,}:? *)+\|? *\r?$"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func hasStrongHint(_ sample: String) -> Bool {
        // JSON, XML and SQL keep their meaning even when string values contain Markdown.
        if sample.hasPrefix("{") || sample.hasPrefix("<") { return false }
        if sample.hasPrefix("["), sample.range(of: #"^\[[^\]\r\n]+\]\("#, options: .regularExpression) == nil { return false }
        let range = NSRange(sample.startIndex..., in: sample)
        return hints.contains { $0.firstMatch(in: sample, range: range) != nil }
    }
    static func allowedLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http" || scheme == "mailto"
    }
    static func parse(_ source: String) throws -> MarkdownDocument {
        try Task.checkCancellation()
        let sample = StructuredText.prefix(source, bytes: StructuredText.displayLimit)
        let parsed = try AttributedString(markdown: sample, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        try Task.checkCancellation()
        var document = MarkdownDocument(text: "", spans: [], blocks: [], truncated: source.utf8.count > sample.utf8.count, hasImages: false)
        var previousID: Int?, length = 0
        var seenItems = Set<Int>()
        for run in parsed.runs {
            try Task.checkCancellation()
            if document.spans.count >= spanLimit { document.truncated = true; break }
            let components = run.presentationIntent?.components ?? []
            if components.contains(where: { if case .tableCell(let column) = $0.kind { return column >= columnLimit }; return false }) {
                document.truncated = true; continue
            }
            let identity = components.first?.identity
            var content = String(parsed[run.range].characters)
            if document.blocks.isEmpty || identity == nil || identity != previousID {
                if document.blocks.count >= blockLimit { document.truncated = true; break }
                if !document.blocks.isEmpty {
                    document.text += "\n"; length += 1
                    document.blocks[document.blocks.count - 1].range.length += 1
                }
                var block = Block(range: NSRange(location: length, length: 0))
                var marker = "", item: (Int, Int)?, ordered = false
                var tableID = 0, columns: [PresentationIntent.TableColumn] = [], row = 0, column: Int?, header = false
                for component in components {
                    switch component.kind {
                    case .header(let level): block.heading = level
                    case .codeBlock: block.code = true
                    case .thematicBreak: block.rule = true
                    case .blockQuote: block.quoteDepth += 1
                    case .listItem(let ordinal): if item == nil { item = (component.identity, ordinal) }
                    case .orderedList: if block.listDepth == 0 { ordered = true }; block.listDepth += 1
                    case .unorderedList: block.listDepth += 1
                    case .table(let value): tableID = component.identity; columns = value
                    case .tableHeaderRow: header = true
                    case .tableRow(let value): row = value
                    case .tableCell(let value): column = value
                    default: break
                    }
                }
                if let column, !columns.isEmpty {
                    if columns.count > columnLimit { document.truncated = true }
                    block.cell = Cell(tableID: tableID, row: row, column: column, columns: min(columns.count, columnLimit), header: header, alignment: columns[min(column, columns.count - 1)].alignment)
                }
                if let item, seenItems.insert(item.0).inserted {
                    marker = ordered ? "\(item.1).\t" : "•\t"
                    if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") { marker = "☑\t"; content.removeFirst(4) }
                    else if content.hasPrefix("[ ] ") { marker = "☐\t"; content.removeFirst(4) }
                }
                document.blocks.append(block)
                document.text += marker; length += marker.utf16.count
                document.blocks[document.blocks.count - 1].range.length += marker.utf16.count
                previousID = identity
            }
            let inline = run.inlinePresentationIntent ?? []
            let image = run.imageURL != nil
            if image {
                let description = content.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                content = "Image : " + (description.isEmpty ? "sans description" : description); document.hasImages = true
            }
            let range = NSRange(location: length, length: content.utf16.count)
            document.spans.append(Span(range: range, bold: inline.contains(.stronglyEmphasized), italic: inline.contains(.emphasized), code: inline.contains(.code) || inline.contains(.inlineHTML) || inline.contains(.blockHTML), strike: inline.contains(.strikethrough), image: image, link: run.link.flatMap { allowedLink($0) ? $0 : nil }))
            document.text += content; length += range.length
            document.blocks[document.blocks.count - 1].range.length += range.length
        }
        return document
    }
}

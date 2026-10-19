import Foundation

enum XMLTextFormatter {
    private final class Node {
        var opening: String
        var closing = ""
        var name: String?
        var children: [Node] = []
        var hasText = false
        var preserve = false
        let id: Int
        init(_ raw: String, name: String? = nil, id: Int) { opening = raw; self.name = name; self.id = id }
    }
    private final class Validator: NSObject, XMLParserDelegate {
        var failure: Error?
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { failure = parseError }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if Task.isCancelled { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
    }
    static func format(_ text: String) throws -> StructuredResult {
        var scan = ByteScanner(text), roots: [Node] = [], stack: [Node] = [], count = 0
        func starts(_ s: String) -> Bool { scan.bytes[scan.position...].starts(with: s.utf8) }
        func raw(_ start: Int) -> String { String(decoding: scan.bytes[start..<scan.position], as: UTF8.self) }
        func append(_ node: Node) { if let parent = stack.last { parent.children.append(node) } else { roots.append(node) } }
        while let c = scan.current {
            try scan.checkpoint(); let start = scan.position
            count += 1
            guard count <= 100_000 else { throw TextIssue(message: "XML limité à 100 000 blocs dans cet aperçu.") }
            if c != 60 {
                while let x = scan.current, x != 60 { scan.position += 1; try scan.checkpoint() }
                // Even whitespace-only text can be significant. Retain it verbatim.
                stack.last?.hasText = true; append(Node(raw(start), id: count)); continue
            }
            var terminator: String?
            if starts("<!--") { terminator = "-->"; scan.position += 4 }
            else if starts("<![CDATA[") { terminator = "]]>"; scan.position += 9; stack.last?.hasText = true }
            else if starts("<?") { terminator = "?>"; scan.position += 2 }
            else if starts("<!") { throw scan.issue("Les déclarations DTD restent consultables dans Original ; leur formatage est désactivé.") }
            if let terminator {
                while scan.current != nil, !starts(terminator) { scan.position += 1; try scan.checkpoint() }
                guard scan.current != nil else { throw scan.issue("Bloc XML non fermé") }
                scan.position += terminator.utf8.count; append(Node(raw(start), id: count)); continue
            }
            scan.position += 1
            let closing = scan.current == 47
            if closing { scan.position += 1 }
            let nameStart = scan.position
            while let x = scan.current, !ByteScanner.isSpace(x), x != 62, x != 47 { scan.position += 1; try scan.checkpoint() }
            let name = String(decoding: scan.bytes[nameStart..<scan.position], as: UTF8.self)
            var quote: UInt8?
            while let x = scan.current {
                try scan.checkpoint(); scan.position += 1
                if let q = quote { if x == q { quote = nil } }
                else if x == 34 || x == 39 { quote = x }
                else if x == 62 { break }
            }
            guard scan.position > start, scan.bytes[scan.position - 1] == 62, quote == nil else { throw scan.issue("Balise XML non fermée") }
            let tag = raw(start)
            if closing {
                guard let node = stack.popLast(), node.name == name else { throw scan.issue("Balise de fermeture inattendue : \(name)", at: start) }
                node.closing = tag
            } else {
                let node = Node(tag, name: name, id: count)
                // Honor inherited xml:space; mixed content is also kept intact below.
                node.preserve = stack.last?.preserve == true || tag.range(of: #"\bxml:space\s*=\s*(["'])preserve\1"#, options: .regularExpression) != nil
                append(node)
                if !tag.hasSuffix("/>") { stack.append(node) }
                guard stack.count <= StructuredText.depthLimit else { throw scan.issue("Imbrication limitée à 128 niveaux") }
            }
        }
        guard stack.isEmpty else { throw scan.issue("Balise XML de fermeture manquante") }
        try Task.checkCancellation()
        let validator = Validator(), parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never; parser.delegate = validator
        guard parser.parse(), validator.failure == nil else {
            try Task.checkCancellation()
            throw TextIssue(message: "XML mal formé", line: max(1, parser.lineNumber), column: max(1, parser.columnNumber))
        }
        var output = "", preserved = false
        func add(_ value: String) throws {
            guard output.utf8.count + value.utf8.count <= StructuredText.outputLimit else { throw TextIssue(message: "Le résultat dépasse 8 Mo.") }
            output += value
        }
        func emit(_ node: Node, depth: Int, inherited: Bool) throws {
            try Task.checkCancellation(); try add(node.opening)
            let preserve = inherited || node.preserve || node.hasText
            if node.preserve || node.hasText { preserved = true }
            for child in node.children {
                if !preserve { try add("\n" + String(repeating: "  ", count: depth + 1)) }
                try emit(child, depth: depth + 1, inherited: preserve)
            }
            if !node.closing.isEmpty {
                if !preserve && !node.children.isEmpty { try add("\n" + String(repeating: "  ", count: depth)) }
                try add(node.closing)
            }
        }
        for node in roots { try emit(node, depth: 0, inherited: false) }
        var branches = 0
        func outline(_ node: Node) -> XMLBranch? {
            guard let name = node.name, branches < 2000 else { return nil }; branches += 1
            return XMLBranch(id: node.id, label: "<\(name)>", children: node.children.compactMap(outline))
        }
        return StructuredResult(text: output, xml: roots.compactMap(outline), note: preserved ? "Espaces et contenu mixte conservés." : nil)
    }
}

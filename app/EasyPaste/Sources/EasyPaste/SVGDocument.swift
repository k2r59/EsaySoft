import Foundation

/// An allowlist of static SVG. Never send the original document to a renderer.
struct SVGDocument: Sendable {
    let canonical: String
    let width: Double, height: Double
    static let inputLimit = 512 * 1024
    static let pasteboardType = "public.svg-image"
    static func looksLikeSVG(_ source: String) -> Bool {
        let sample = StructuredText.prefix(source, bytes: 4096)
        if sample.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<"), sample.localizedCaseInsensitiveContains("<!DOCTYPE"), sample.range(of: #"<(?:[A-Za-z_][\w.-]*:)?svg(?:\s|/?>)"#, options: .regularExpression) != nil { return true }
        return sample.range(of: #"(?is)^\s*(?:\uFEFF)?\s*(?:<\?xml[^?]*\?>\s*)?(?:<!--.*?-->\s*)*<(?:[A-Za-z_][\w.-]*:)?svg(?:\s|/?>)"#, options: .regularExpression) != nil
    }
    static func parse(_ source: String) throws -> SVGDocument {
        try Task.checkCancellation()
        guard source.utf8.count <= inputLimit else { throw TextIssue(message: "SVG limité à 512 Ko. Le source reste disponible.") }
        // DTDs are refused before XMLParser sees them, including entity expansion.
        guard !source.localizedCaseInsensitiveContains("<!DOCTYPE"), !source.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw TextIssue(message: "Aperçu SVG bloqué : déclarations DTD ou entités.")
        }
        let delegate = SVGValidator(), parser = XMLParser(data: Data(source.utf8))
        parser.shouldProcessNamespaces = true; parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never; parser.delegate = delegate
        let valid = parser.parse()
        try Task.checkCancellation()
        if let failure = delegate.failure { throw failure }
        guard valid, delegate.rootSeen, delegate.stack.isEmpty else {
            throw TextIssue(message: "SVG mal formé", line: max(1, parser.lineNumber), column: max(1, parser.columnNumber))
        }
        try delegate.validateReferences()
        guard delegate.output.utf8.count <= inputLimit else { throw TextIssue(message: "SVG reconstruit trop volumineux. Le source reste disponible.") }
        return SVGDocument(canonical: delegate.output, width: delegate.width, height: delegate.height)
    }
}

private final class SVGValidator: NSObject, XMLParserDelegate {
    struct Reference { let ancestors: [String], target: String, paint: Bool }
    var output = "", width = 300.0, height = 150.0, rootSeen = false
    var failure: TextIssue?
    var stack: [(name: String, id: String?)] = []
    private var nodes = 0, numbers = 0
    private var ids: [String: String] = [:], references: [Reference] = []
    private static let names: Set<String> = ["svg", "g", "defs", "title", "desc", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan", "linearGradient", "radialGradient", "stop", "clipPath"]
    private static let global: Set<String> = ["id", "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "opacity", "transform", "color", "clip-path", "clip-rule", "vector-effect", "display", "visibility"]
    private static let local: [String: Set<String>] = [
        "svg": ["width", "height", "viewBox", "preserveAspectRatio", "version"], "path": ["d", "pathLength"],
        "rect": ["x", "y", "width", "height", "rx", "ry"], "circle": ["cx", "cy", "r"], "ellipse": ["cx", "cy", "rx", "ry"],
        "line": ["x1", "y1", "x2", "y2"], "polyline": ["points"], "polygon": ["points"],
        "text": ["x", "y", "dx", "dy", "font-family", "font-size", "font-weight", "font-style", "text-anchor", "dominant-baseline", "xml:space"],
        "tspan": ["x", "y", "dx", "dy", "font-family", "font-size", "font-weight", "font-style", "text-anchor", "xml:space"],
        "linearGradient": ["x1", "y1", "x2", "y2", "gradientUnits", "gradientTransform", "spreadMethod"],
        "radialGradient": ["cx", "cy", "r", "fx", "fy", "fr", "gradientUnits", "gradientTransform", "spreadMethod"],
        "stop": ["offset", "stop-color", "stop-opacity"], "clipPath": ["clipPathUnits"]
    ]
    private static let number = try! NSRegularExpression(pattern: #"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?"#)
    private func reject(_ parser: XMLParser, _ reason: String) {
        if failure == nil { failure = TextIssue(message: "Aperçu SVG bloqué : " + reason, line: max(1, parser.lineNumber)) }
        parser.abortParsing()
    }
    private func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private func numeric(_ value: String, characters: String = #"0-9eE+.,\s%-"#) -> Bool {
        guard matches(value, "^[" + characters + "]+$") else { return false }
        let all = Self.number.matches(in: value, range: NSRange(value.startIndex..., in: value)); numbers += all.count
        return !all.isEmpty && numbers <= 50_000 && all.allSatisfy { match in
            guard let range = Range(match.range, in: value), let number = Double(value[range]) else { return false }
            return number.isFinite && abs(number) <= 1_000_000
        }
    }
    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        guard failure == nil else { return }
        if Task.isCancelled { parser.abortParsing(); return }
        nodes += 1
        guard nodes <= 2000, stack.count < 32, attributes.count <= 64 else { reject(parser, "document trop complexe."); return }
        guard namespaceURI == nil || namespaceURI == "" || namespaceURI == "http://www.w3.org/2000/svg", Self.names.contains(name) else { reject(parser, "élément « \(name) » non autorisé."); return }
        guard !stack.isEmpty || (!rootSeen && name == "svg") else { reject(parser, "racine SVG attendue."); return }
        guard name != "svg" || !rootSeen else { reject(parser, "SVG imbriqués non pris en charge."); return }
        let allowed = Self.global.union(Self.local[name] ?? [])
        var values: [String: String] = [:]
        for (key, value) in attributes {
            guard value.utf8.count <= 256 * 1024 else { reject(parser, "attribut trop volumineux."); return }
            if key == "style" {
                // Only simple presentation properties. No stylesheet, escape, URL import or selector.
                for declaration in value.split(separator: ";", omittingEmptySubsequences: true) {
                    let pair = declaration.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    guard pair.count == 2 else { reject(parser, "style non pris en charge."); return }
                    let property = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard allowed.contains(property), property != "id" else { reject(parser, "propriété de style « \(property) » non autorisée."); return }
                    values[property] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                guard allowed.contains(key) else { reject(parser, "attribut « \(key) » non autorisé."); return }
                if values[key] == nil { values[key] = value.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        let id = values["id"]
        if let id {
            guard matches(id, #"^[A-Za-z_][A-Za-z0-9_.-]{0,63}$"#), ids[id] == nil else { reject(parser, "identifiant invalide ou répété."); return }
            ids[id] = name
        }
        stack.append((name, id))
        for (key, value) in values {
            guard validate(value, key: key) else { reject(parser, "valeur de « \(key) » non autorisée."); return }
        }
        if !rootSeen {
            rootSeen = true
            let box = values["viewBox"]?.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { Double($0) }
            width = values["width"].flatMap { Double($0.hasSuffix("px") ? String($0.dropLast(2)) : $0) } ?? (box?.count == 4 ? box![2] : 300)
            height = values["height"].flatMap { Double($0.hasSuffix("px") ? String($0.dropLast(2)) : $0) } ?? (box?.count == 4 ? box![3] : 150)
            guard width >= 0.001, height >= 0.001, width.isFinite, height.isFinite else { reject(parser, "dimensions invalides."); return }
            if values["viewBox"] == nil { values["viewBox"] = "0 0 \(width) \(height)" }
            let scale = min(1, 8192 / max(width, height))
            values["width"] = String(max(1, width * scale)); values["height"] = String(max(1, height * scale))
            output += "<svg xmlns=\"http://www.w3.org/2000/svg\""
        } else { output += "<" + name }
        for key in values.keys.sorted() { output += " \(key)=\"\(escaped(values[key]!))\"" }
        output += ">"
    }
    private func validate(_ value: String, key: String) -> Bool {
        switch key {
        case "id": return true
        case "fill", "stroke", "color", "stop-color", "clip-path":
            if matches(value, #"^url\(#[A-Za-z_][A-Za-z0-9_.-]{0,63}\)$"#) {
                references.append(Reference(ancestors: stack.compactMap(\.id), target: String(value.dropFirst(5).dropLast()), paint: key != "clip-path"))
                return references.count <= 256
            }
            if key == "clip-path" { return value == "none" }
            if matches(value, #"^(?:#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})|[A-Za-z]{1,30})$"#) { return true }
            guard matches(value, #"^(?:rgb|rgba|hsl|hsla)\([0-9+.,\s%/-]+\)$"#), let start = value.firstIndex(of: "(") else { return false }
            return numeric(String(value[value.index(after: start)..<value.index(before: value.endIndex)]), characters: #"0-9+.,\s%/-"#)
        case "d": return value.isEmpty || numeric(value, characters: #"MmZzLlHhVvCcSsQqTtAa0-9eE+.,\s-"#)
        case "transform", "gradientTransform":
            guard matches(value, #"^(?:(?:matrix|translate|scale|rotate|skewX|skewY)\s*\([0-9eE+.,\s-]+\)\s*)+$"#) else { return false }
            let clean = value.replacingOccurrences(of: #"[A-DF-Za-df-z()]"#, with: " ", options: .regularExpression)
            return numeric(clean)
        case "viewBox":
            let parts = value.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { Double($0) }
            return parts.count == 4 && parts[2] > 0 && parts[3] > 0 && numeric(value)
        case "fill-rule", "clip-rule": return ["nonzero", "evenodd"].contains(value)
        case "stroke-linecap": return ["butt", "round", "square"].contains(value)
        case "stroke-linejoin": return ["miter", "round", "bevel"].contains(value)
        case "vector-effect": return ["none", "non-scaling-stroke"].contains(value)
        case "display": return ["none", "inline"].contains(value)
        case "visibility": return ["visible", "hidden", "collapse"].contains(value)
        case "gradientUnits", "clipPathUnits": return ["userSpaceOnUse", "objectBoundingBox"].contains(value)
        case "spreadMethod": return ["pad", "reflect", "repeat"].contains(value)
        case "preserveAspectRatio": return matches(value, #"^(?:none|x(?:Min|Mid|Max)Y(?:Min|Mid|Max)(?:\s+(?:meet|slice))?)$"#)
        case "font-family": return matches(value, #"^[A-Za-z0-9 _,'-]{1,100}$"#)
        case "font-weight": return ["normal", "bold", "100", "200", "300", "400", "500", "600", "700", "800", "900"].contains(value)
        case "font-style": return ["normal", "italic", "oblique"].contains(value)
        case "text-anchor": return ["start", "middle", "end"].contains(value)
        case "dominant-baseline": return ["auto", "middle", "central", "hanging", "alphabetic", "text-before-edge", "text-after-edge"].contains(value)
        case "xml:space": return ["default", "preserve"].contains(value)
        case "version": return ["1.0", "1.1", "2.0"].contains(value)
        case "stroke-dasharray": return value == "none" || numeric(value)
        default: return numeric(value.hasSuffix("px") ? String(value.dropLast(2)) : value)
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard failure == nil, stack.last?.name == name else { return }
        output += "</" + name + ">"; stack.removeLast()
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard failure == nil else { return }
        guard string.utf8.count <= 64 * 1024 else { reject(parser, "texte trop volumineux."); return }
        if ["text", "tspan", "title", "desc"].contains(stack.last?.name ?? "") { output += escaped(string) }
        else if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reject(parser, "texte hors d’un élément textuel.") }
    }
    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { reject(parser, "encodage invalide."); return }
        self.parser(parser, foundCharacters: text)
    }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) { reject(parser, "instruction de traitement non autorisée.") }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { reject(parser, "entité externe non autorisée."); return nil }
    func validateReferences() throws {
        var edges: [String: Set<String>] = [:]
        for reference in references {
            let expected: Set<String> = reference.paint ? ["linearGradient", "radialGradient"] : ["clipPath"]
            guard let kind = ids[reference.target], expected.contains(kind) else { throw TextIssue(message: "Aperçu SVG bloqué : référence locale invalide.") }
            for ancestor in reference.ancestors { edges[ancestor, default: []].insert(reference.target) }
        }
        var visited = Set<String>(), active = Set<String>()
        func visit(_ id: String, depth: Int) throws {
            guard !active.contains(id), depth < 32 else { throw TextIssue(message: "Aperçu SVG bloqué : références circulaires.") }
            if visited.contains(id) { return }; active.insert(id)
            for next in edges[id] ?? [] { try visit(next, depth: depth + 1) }
            active.remove(id); visited.insert(id)
        }
        for id in edges.keys { try visit(id, depth: 0) }
    }
}

import AppKit
import ApplicationServices

/// Page provenance is metadata only: never infer it from an arbitrary link in
/// copied content, and never render HTML or fetch a page to discover it.
enum BrowserOrigin {
    static let chromiumType = NSPasteboard.PasteboardType("org.chromium.source-url")
    private static let asciiURL = CharacterSet(charactersIn: String((33...126).compactMap(UnicodeScalar.init).map(Character.init)))
    static func url(_ value: String?) -> URL? {
        guard let value, value.utf8.count <= 8192, !value.isEmpty,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let encoded = value.addingPercentEncoding(withAllowedCharacters: asciiURL), encoded.utf8.count <= 8192,
              let parts = URLComponents(string: encoded, encodingInvalidCharacters: false), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
    static func browser(_ id: String) -> Bool {
        ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "company.thebrowser.Browser",
         "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "com.apple.Safari", "com.apple.SafariTechnologyPreview",
         "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"].contains(id)
    }
    static func metadata(_ items: [NSPasteboardItem]) -> String? {
        // Extension metadata identifies the actual tab, while Chromium's own
        // source may be the extension's popup. Extension metadata wins.
        let enriched = items.compactMap { $0.data(forType: .html) }.compactMap(extensionURL)
        if !enriched.isEmpty { return unique(enriched) }
        return unique(items.compactMap { url($0.string(forType: chromiumType))?.absoluteString })
    }
    private static func unique(_ values: [String]) -> String? { let set = Set(values); return set.count == 1 ? set.first : nil }

    private static let entities = try! NSRegularExpression(pattern: #"&(#(?:x|X)[0-9a-fA-F]{1,6}|#[0-9]{1,7}|amp|quot|apos|lt|gt);"#)
    static func extensionURL(_ data: Data) -> String? {
        // Bound work independently of clipboard size. This fits an 8192-byte
        // URL even when every '&' expands to '&amp;' in an HTML attribute.
        let bytes = Array(data.prefix(65_536))
        guard String(decoding: bytes, as: UTF8.self).range(of: "easypaste-source-url", options: .caseInsensitive) != nil else { return nil }
        var scanner = HTMLHeadScanner(bytes: bytes)
        return unique(scanner.sources())
    }

    /// A small, non-rendering tokenizer for head metadata. Quoted attributes,
    /// comments and raw/inert elements cannot introduce fake <meta> tokens.
    private struct HTMLHeadScanner {
        let bytes: [UInt8]
        var cursor = 0
        private func space(_ byte: UInt8) -> Bool { [9, 10, 12, 13, 32].contains(byte) }
        private func lower(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
        private func letter(_ byte: UInt8) -> Bool { (97...122).contains(lower(byte)) }
        private func matches(_ text: [UInt8], at index: Int, folded: Bool = false) -> Bool {
            guard index >= 0, index + text.count <= bytes.count else { return false }
            for offset in text.indices {
                let byte = folded ? lower(bytes[index + offset]) : bytes[index + offset]
                if byte != text[offset] { return false }
            }
            return true
        }
        private func endOfTag(from start: Int) -> Int? {
            var quote: UInt8? = nil
            var index = start
            while index < bytes.count {
                let byte = bytes[index]
                if let open = quote { if byte == open { quote = nil } }
                else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 62 { return index }
                index += 1
            }
            return nil
        }
        private func endOfRawElement(_ name: String, from start: Int) -> Int? {
            let closing = Array(("</" + name).utf8)
            var index = start
            while index < bytes.count {
                if bytes[index] == 60, matches(closing, at: index, folded: true) {
                    let next = index + closing.count
                    if next < bytes.count, space(bytes[next]) || bytes[next] == 62 || bytes[next] == 47,
                       let end = endOfTag(from: next) { return end + 1 }
                }
                index += 1
            }
            return nil
        }
        private func attributes(from start: Int, to end: Int) -> [String: String]? {
            var index = start, values: [String: String] = [:]
            while index < end {
                while index < end, space(bytes[index]) { index += 1 }
                if index == end || (bytes[index] == 47 && index + 1 == end) { break }
                let nameStart = index
                guard letter(bytes[index]) else { return nil }
                while index < end, !space(bytes[index]), ![61, 47].contains(bytes[index]) {
                    guard letter(bytes[index]) || (48...57).contains(bytes[index]) || [45, 95, 58].contains(bytes[index]) else { return nil }
                    index += 1
                }
                let name = String(decoding: bytes[nameStart..<index].map(lower), as: UTF8.self)
                guard values[name] == nil, values.count < 64 else { return nil }
                while index < end, space(bytes[index]) { index += 1 }
                var value = ""
                if index < end, bytes[index] == 61 {
                    index += 1
                    while index < end, space(bytes[index]) { index += 1 }
                    guard index < end else { return nil }
                    if bytes[index] == 34 || bytes[index] == 39 {
                        let quote = bytes[index]; index += 1
                        let valueStart = index
                        while index < end, bytes[index] != quote { index += 1 }
                        guard index < end else { return nil }
                        value = String(decoding: bytes[valueStart..<index], as: UTF8.self); index += 1
                        guard index == end || space(bytes[index]) || bytes[index] == 47 else { return nil }
                    } else {
                        let valueStart = index
                        while index < end, !space(bytes[index]) {
                            guard ![34, 39, 60, 61, 96].contains(bytes[index]) else { return nil }
                            index += 1
                        }
                        value = String(decoding: bytes[valueStart..<index], as: UTF8.self)
                    }
                }
                values[name] = value
            }
            return values
        }
        mutating func sources() -> [String] {
            var result: [String] = [], templateDepth = 0
            let headTags: Set<String> = ["html", "head", "meta", "base", "link", "title", "script", "style", "noscript", "noframes", "template"]
            let rawTags: Set<String> = ["script", "style", "title", "textarea", "noscript", "noframes"]
            if matches([239, 187, 191], at: 0) { cursor = 3 }
            while cursor < bytes.count {
                if space(bytes[cursor]) { cursor += 1; continue }
                if templateDepth > 0, bytes[cursor] != 60 { cursor += 1; continue }
                // Ordinary body text also ends a head-less metadata fragment.
                guard bytes[cursor] == 60 else { break }
                if matches(Array("<!--".utf8), at: cursor) {
                    cursor += 4
                    while cursor < bytes.count, !matches(Array("-->".utf8), at: cursor) { cursor += 1 }
                    guard cursor < bytes.count else { break }
                    cursor += 3; continue
                }
                let opening = cursor; cursor += 1
                guard cursor < bytes.count else { break }
                if bytes[cursor] == 33 || bytes[cursor] == 63 {
                    guard let end = endOfTag(from: cursor + 1) else { break }
                    cursor = end + 1; continue
                }
                let closing = bytes[cursor] == 47
                if closing { cursor += 1 }
                guard cursor < bytes.count, letter(bytes[cursor]) else { break }
                let nameStart = cursor
                while cursor < bytes.count, letter(bytes[cursor]) || (48...57).contains(bytes[cursor]) || bytes[cursor] == 45 { cursor += 1 }
                let name = String(decoding: bytes[nameStart..<cursor].map(lower), as: UTF8.self)
                guard cursor < bytes.count, space(bytes[cursor]) || bytes[cursor] == 47 || bytes[cursor] == 62,
                      let end = endOfTag(from: cursor) else { break }
                let attributeStart = cursor; cursor = end + 1
                if name == "template" { templateDepth += closing ? -min(templateDepth, 1) : 1; continue }
                if templateDepth == 0, name == "body" || (closing && ["head", "html"].contains(name)) || !headTags.contains(name) { break }
                if !closing, rawTags.contains(name) {
                    guard let after = endOfRawElement(name, from: cursor) else { break }
                    cursor = after; continue
                }
                if templateDepth > 0 { continue }
                if !closing, name == "meta", let values = attributes(from: attributeStart, to: end),
                   values["name"]?.lowercased() == "easypaste-source-url", let content = values["content"],
                   let source = BrowserOrigin.url(BrowserOrigin.decodeEntities(content)) { result.append(source.absoluteString) }
                // A defensive progress check keeps malformed input bounded too.
                if cursor <= opening { break }
            }
            return result
        }
    }
    private static func decodeEntities(_ value: String) -> String {
        let result = NSMutableString(string: value)
        for match in entities.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length)).reversed() {
            let entity = (value as NSString).substring(with: match.range(at: 1))
            var decoded = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">"][entity]
            if entity.hasPrefix("#") {
                let hex = entity.hasPrefix("#x") || entity.hasPrefix("#X")
                if let number = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) { decoded = String(scalar) }
            }
            if let decoded { result.replaceCharacters(in: match.range, with: decoded) }
        }
        return result as String
    }
}

struct BrowserPageContext {
    let sourceURL: String
    let frame: CGRect
    func source(for rect: CGRect, confirmed: BrowserPageContext?) -> String? {
        guard let confirmed, sourceURL == confirmed.sourceURL, frame == confirmed.frame,
              !rect.isEmpty, frame.contains(rect) else { return nil }
        return sourceURL
    }
}

enum BrowserPageReader {
    /// Called on a worker only when new clipboard content arrives, or once at
    /// capture time. No polling of browser tabs, scripts or network requests.
    static func read(pid: pid_t, bundleID: String, requireFocused: Bool = true) -> BrowserPageContext? {
        guard BrowserOrigin.browser(bundleID), AXIsProcessTrusted() else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.02)
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
        }
        func element(_ object: CFTypeRef?) -> AXUIElement? {
            guard let object, CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
            return (object as! AXUIElement)
        }
        func focused() -> Bool {
            guard let app = element(value(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute)) else { return false }
            var actual: pid_t = 0
            return AXUIElementGetPid(app, &actual) == .success && actual == pid
        }
        guard !requireFocused || focused() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(value(app, kAXFocusedWindowAttribute)) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        if let v = value(window, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &point) }
        if let v = value(window, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &size) }
        func pageURL(_ item: AXUIElement) -> String? {
            let role = value(item, kAXRoleAttribute) as? String
            guard role == kAXWindowRole || role == "AXWebArea" else { return nil }
            for key in role == "AXWebArea" ? [kAXURLAttribute, kAXDocumentAttribute] : [kAXDocumentAttribute] {
                let raw = value(item, key)
                if let url = BrowserOrigin.url((raw as? String) ?? (raw as? URL)?.absoluteString) { return url.absoluteString }
            }
            return nil
        }
        var source = pageURL(window)
        var current = element(value(app, kAXFocusedUIElementAttribute))
        for _ in 0..<8 where source == nil {
            guard let item = current else { break }
            source = pageURL(item); current = element(value(item, kAXParentAttribute))
        }
        // A bounded breadth-first walk of browser chrome to the web area only.
        // Never descend into document links and mistake one for its page URL.
        var queue: [(AXUIElement, Int)] = [(window, 0)], visited = 0
        while source == nil, !queue.isEmpty, visited < 32, ProcessInfo.processInfo.systemUptime < deadline {
            let (item, depth) = queue.removeFirst(); visited += 1
            source = pageURL(item)
            guard source == nil, depth < 5, value(item, kAXRoleAttribute) as? String != "AXWebArea" else { continue }
            var children: CFArray?
            AXUIElementSetMessagingTimeout(item, 0.02)
            if AXUIElementCopyAttributeValues(item, kAXChildrenAttribute as CFString, 0, 12, &children) == .success,
               let children = children as? [AXUIElement] { queue.append(contentsOf: children.prefix(32 - visited).map { ($0, depth + 1) }) }
        }
        guard let source, !requireFocused || focused() else { return nil }
        return BrowserPageContext(sourceURL: source, frame: CGRect(origin: point, size: size))
    }
}

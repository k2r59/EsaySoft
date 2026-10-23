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
              let encoded = value.addingPercentEncoding(withAllowedCharacters: asciiURL),
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

    private static let tags = try! NSRegularExpression(pattern: "<meta\\s[^>]{0,4096}>", options: .caseInsensitive)
    private static let attributes = try! NSRegularExpression(pattern: #"([a-zA-Z][a-zA-Z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#)
    private static let entities = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|amp|quot|apos|lt|gt);"#)
    static func extensionURL(_ data: Data) -> String? {
        // A bounded scan of the head; no TextKit/WebKit HTML importer.
        var html = String(decoding: data.prefix(65_536), as: UTF8.self)
        guard html.range(of: "easypaste-source-url", options: .caseInsensitive) != nil else { return nil }
        if let end = html.range(of: "</head>", options: .caseInsensitive) { html = String(html[..<end.lowerBound]) }
        else if let body = html.range(of: "<body", options: .caseInsensitive) { html = String(html[..<body.lowerBound]) }
        html = html.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        let ns = html as NSString
        var sources: [String] = []
        for tag in tags.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let text = ns.substring(with: tag.range), source = text as NSString
            var values: [String: String] = [:]; var duplicates = false
            for attr in attributes.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                let name = source.substring(with: attr.range(at: 1)).lowercased()
                let range = attr.range(at: 2).location != NSNotFound ? attr.range(at: 2) : attr.range(at: 3)
                if values[name] != nil { duplicates = true }
                values[name] = source.substring(with: range)
            }
            guard !duplicates, values["name"]?.lowercased() == "easypaste-source-url", let content = values["content"],
                  let result = url(decodeEntities(content)) else { continue }
            sources.append(result.absoluteString)
        }
        return unique(sources)
    }
    private static func decodeEntities(_ value: String) -> String {
        let result = NSMutableString(string: value)
        for match in entities.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length)).reversed() {
            let entity = (value as NSString).substring(with: match.range(at: 1))
            var decoded = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">"][entity]
            if entity.hasPrefix("#") {
                let hex = entity.hasPrefix("#x")
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

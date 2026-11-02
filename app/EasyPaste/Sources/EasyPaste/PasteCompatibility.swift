import AppKit
import ApplicationServices

/// Exceptions are destination-specific. Clipboard capture/storage and ordinary
/// rich pastes never pass through a conversion here.
enum PasteCompatibilityPolicy {
    static func fileZillaDialog(bundleID: String, role: String?, title: String?) -> Bool {
        bundleID == "org.filezilla-project.filezilla" && role == kAXDialogSubrole &&
            ["Gestionnaire de sites", "Site Manager"].contains(title ?? "")
    }

    static func sheetsValues(bundleID: String, plain: Bool, pageURL: String?) -> Bool {
        guard plain, BrowserOrigin.browser(bundleID), let pageURL,
              let url = URLComponents(string: pageURL), url.scheme == "https",
              url.host?.lowercased() == "docs.google.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        let parts = url.path.split(separator: "/")
        return parts.count >= 3 && parts[0] == "spreadsheets" && parts[1] == "d" &&
            !parts[2].isEmpty && parts[2] != "e"
    }

    /// AX ranges use UTF-16, not Swift character offsets. Never replace a whole
    /// field when its insertion point is unavailable, or split a surrogate pair.
    static func inserting(_ text: String, into value: String, selection: NSRange) -> (value: String, cursor: Int)? {
        guard text.utf8.count <= 65_536, value.utf8.count <= 65_536,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              selection.location >= 0, selection.length >= 0,
              selection.location <= value.utf16.count,
              selection.length <= value.utf16.count - selection.location else { return nil }
        let units = Array(value.utf16)
        func boundary(_ offset: Int) -> Bool {
            offset == 0 || offset == units.count || !(0xDC00...0xDFFF).contains(units[offset])
        }
        guard boundary(selection.location), boundary(selection.location + selection.length) else { return nil }
        let result = (value as NSString).replacingCharacters(in: selection, with: text)
        return (result, selection.location + text.utf16.count)
    }

    /// Short Unicode events for a secure NSTextField which exposes no writable
    /// selection. No existing password is read, and no command/return is sent.
    static func secureInput(_ text: String) -> [CGEvent]? {
        guard !text.isEmpty, text.utf16.count <= 1_024,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        var chunks: [[UniChar]] = [[]]
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if chunks[chunks.count - 1].count + units.count > 16 { chunks.append([]) }
            chunks[chunks.count - 1].append(contentsOf: units)
        }
        var events: [CGEvent] = []
        for chunk in chunks {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return nil }
            for event in [down, up] {
                event.flags = []
                chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
            }
            events.append(contentsOf: [down, up])
        }
        return events
    }
}

@MainActor enum PasteCompatibility {
    enum Result { case standard, sheetsValues, inserted, unavailable }
    struct RenameContext {
        let window: AXUIElement
        let name: String
        let selection: CFRange
    }

    /// FileZilla destroys its inline site-name editor when the shelf takes focus.
    /// Remember only this editor, never credentials or ordinary field contents.
    static func captureRename(destination: NSRunningApplication?) -> RenameContext? {
        guard let destination, destination.bundleIdentifier == "org.filezilla-project.filezilla",
              NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier,
              AXIsProcessTrusted() else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.12
        func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.01)
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return value as! AXUIElement
        }
        let app = AXUIElementCreateApplication(destination.processIdentifier)
        guard let window = element(read(app, kAXFocusedWindowAttribute)),
              PasteCompatibilityPolicy.fileZillaDialog(bundleID: destination.bundleIdentifier!, role: read(window, kAXSubroleAttribute) as? String, title: read(window, kAXTitleAttribute) as? String),
              let field = element(read(app, kAXFocusedUIElementAttribute)),
              read(field, kAXRoleAttribute) as? String == kAXTextFieldRole,
              read(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let parent = element(read(field, kAXParentAttribute)), CFEqual(parent, window),
              let name = read(field, kAXValueAttribute) as? String, name.utf8.count <= 4096,
              let rawRange = read(field, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &selection),
              PasteCompatibilityPolicy.inserting("", into: name, selection: NSRange(location: selection.location, length: selection.length)) != nil else { return nil }
        return RenameContext(window: window, name: name, selection: selection)
    }

    static func prepare(destination: NSRunningApplication, plain: Bool, rename: RenameContext? = nil) async -> Result {
        let id = destination.bundleIdentifier ?? ""
        guard id == "org.filezilla-project.filezilla" || (plain && BrowserOrigin.browser(id)) else { return .standard }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier else { return .unavailable }
        if id != "org.filezilla-project.filezilla" {
            let pid = destination.processIdentifier
            let page = await Task.detached(priority: .userInitiated) { BrowserPageReader.read(pid: pid, bundleID: id) }.value
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .unavailable }
            return PasteCompatibilityPolicy.sheetsValues(bundleID: id, plain: plain, pageURL: page?.sourceURL) ? .sheetsValues : .standard
        }

        let app = AXUIElementCreateApplication(destination.processIdentifier)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.02)
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        guard let window = element(read(app, kAXFocusedWindowAttribute)) else { return .standard }
        let role = read(window, kAXSubroleAttribute) as? String
        let title = read(window, kAXTitleAttribute) as? String
        // AXDialog is a window subrole on macOS. Other windows retain Cmd+V.
        guard PasteCompatibilityPolicy.fileZillaDialog(bundleID: id, role: role, title: title) else { return .standard }
        if let rename {
            guard CFEqual(rename.window, window),
                  let current = element(read(app, kAXFocusedUIElementAttribute)) else { return .unavailable }
            if read(current, kAXRoleAttribute) as? String != kAXTextFieldRole {
                guard let children = read(window, kAXChildrenAttribute) as? [AXUIElement],
                      let button = children.prefix(32).first(where: {
                          read($0, kAXRoleAttribute) as? String == kAXButtonRole &&
                          ["Renommer", "Rename"].contains(read($0, kAXTitleAttribute) as? String ?? "")
                      }), NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier,
                      AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return .unavailable }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            guard let editor = element(read(app, kAXFocusedUIElementAttribute)),
                  let parent = element(read(editor, kAXParentAttribute)), CFEqual(parent, window),
                  read(editor, kAXValueAttribute) as? String == rename.name else { return .unavailable }
            var selection = rename.selection
            guard let range = AXValueCreate(.cfRange, &selection),
                  AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) == .success else { return .unavailable }
        }
        guard let field = element(read(app, kAXFocusedUIElementAttribute)),
              read(field, kAXRoleAttribute) as? String == kAXTextFieldRole,
              read(field, kAXEnabledAttribute) as? Bool == true,
              let fieldWindow = element(read(field, kAXWindowAttribute)), CFEqual(fieldWindow, window),
              let text = NSPasteboard.general.string(forType: .string), text.utf8.count <= 65_536,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .unavailable }

        func unchanged() -> Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier,
                  let current = element(read(app, kAXFocusedUIElementAttribute)), CFEqual(current, field),
                  let currentWindow = element(read(app, kAXFocusedWindowAttribute)), CFEqual(currentWindow, window) else { return false }
            return true
        }
        var writable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &writable) == .success, writable.boolValue {
            guard unchanged() else { return .unavailable }
            // A timeout may occur after insertion: never retry or send Cmd+V.
            return AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, text as CFString) == .success ? .inserted : .unavailable
        }
        if read(field, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
            guard let events = PasteCompatibilityPolicy.secureInput(text), unchanged() else { return .unavailable }
            // FileZilla's native secure field accepts text input at its cursor.
            // Recheck the focused field before every pair, never retry a prefix.
            for index in stride(from: 0, to: events.count, by: 2) {
                guard unchanged() else { return .unavailable }
                events[index].postToPid(destination.processIdentifier)
                events[index + 1].postToPid(destination.processIdentifier)
            }
            return .inserted
        }
        // NSTextField implementations may expose only value + selection range.
        guard let value = read(field, kAXValueAttribute) as? String,
              let rawRange = read(field, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else { return .unavailable }
        var selection = CFRange()
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &selection),
              let edit = PasteCompatibilityPolicy.inserting(text, into: value, selection: NSRange(location: selection.location, length: selection.length)),
              AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &writable) == .success, writable.boolValue,
              unchanged(), read(field, kAXValueAttribute) as? String == value,
              let currentRange = read(field, kAXSelectedTextRangeAttribute), CFEqual(currentRange, rawRange) else { return .unavailable }
        guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, edit.value as CFString) == .success else { return .unavailable }
        var cursor = CFRange(location: edit.cursor, length: 0)
        if let range = AXValueCreate(.cfRange, &cursor) {
            AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, range)
        }
        return .inserted
    }
}

import AppKit

enum ClipboardReader {
    static let limit = 20_000_000
    static func read(_ pb: NSPasteboard, source: String, sourceID: String, exclusions: Set<String>) throws -> Clip? {
        let items = pb.pasteboardItems ?? []
        guard ClipboardPrivacy.allows(types: Set(items.flatMap { $0.types.map(\.rawValue) }), sourceID: sourceID, extra: exclusions) else { return nil }
        var bytes = 0
        var representations: [[ClipRepresentation]] = []
        for item in items {
            var row: [ClipRepresentation] = []
            // PNG and TIFF usually encode the same image. Keep one full-resolution representation.
            let types: [NSPasteboard.PasteboardType] = [.string, .rtf, .html, item.types.contains(.png) ? .png : .tiff, .fileURL, .URL]
            for type in types where item.types.contains(type) {
                guard let data = item.data(forType: type) else { continue }
                bytes += data.count
                guard bytes <= limit else { throw NSError(domain: "EasyPaste", code: 20, userInfo: [NSLocalizedDescriptionKey: "Copie ignorée : elle dépasse 20 Mo."]) }
                row.append(.init(type: type.rawValue, data: data))
            }
            if !row.isEmpty { representations.append(row) }
        }
        guard !representations.isEmpty else { return nil }
        let flat = representations.flatMap { $0 }
        var text = pb.string(forType: .string) ?? pb.string(forType: .URL) ?? ""
        if text.isEmpty, let rtf = flat.first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue })?.data {
            text = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string ?? ""
        }
        let files = flat.filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }.compactMap { String(data: $0.data, encoding: .utf8) }.compactMap(URL.init(string:))
        if !files.isEmpty { text = files.map(\.path).joined(separator: "\n") }
        let kind = Clip.kind(for: text, hasImage: flat.contains { [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue].contains($0.type) }, hasFiles: !files.isEmpty)
        let title = files.isEmpty ? (text.isEmpty ? "Image copiée" : String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(90))) : files.map(\.lastPathComponent).joined(separator: ", ")
        return Clip(title: title, text: text, source: source, sourceID: sourceID, kind: kind, fingerprint: "", payload: ClipPayload(representations: representations))
    }
}

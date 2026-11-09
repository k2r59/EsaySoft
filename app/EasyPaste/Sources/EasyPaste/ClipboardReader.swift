import AppKit
import ImageIO

enum ClipboardReader {
    static let limit = 20_000_000
    static let remoteType = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")
    static let remoteSourceID = "com.apple.universalclipboard"
    static func read(_ pb: NSPasteboard, source: String, sourceID: String, exclusions: Set<String>) throws -> Clip? {
        let items = pb.pasteboardItems ?? []
        let types = Set((pb.types ?? []).map(\.rawValue) + items.flatMap { $0.types.map(\.rawValue) })
        let remote = types.contains(remoteType.rawValue)
        // The foreground Mac app did not copy content arriving through Handoff.
        // Honour a declared source and confidential markers from that device.
        let declaredSource = remote && types.contains("org.nspasteboard.source") ? pb.string(forType: .init("org.nspasteboard.source")) : nil
        let effectiveSourceID = remote ? (declaredSource.flatMap { $0.isEmpty ? nil : $0 } ?? remoteSourceID) : sourceID
        guard ClipboardPrivacy.allows(types: types, sourceID: effectiveSourceID, extra: exclusions) else { return nil }
        var bytes = 0
        var representations: [[ClipRepresentation]] = []
        for item in items {
            var row: [ClipRepresentation] = []
            // PNG and TIFF usually encode the same image. Keep one full-resolution representation.
            let types: [NSPasteboard.PasteboardType] = [.string, .rtf, .html, .init(SVGDocument.pasteboardType), .init("image/svg+xml"), item.types.contains(.png) ? .png : .tiff, .fileURL, .URL]
            for type in types where item.types.contains(type) {
                guard let data = item.data(forType: type) else { continue }
                bytes += data.count
                guard bytes <= limit else { throw NSError(domain: "EasyPaste", code: 20, userInfo: [NSLocalizedDescriptionKey: "Copie ignorée : elle dépasse 20 Mo."]) }
                row.append(.init(type: type.rawValue, data: data))
            }
            if !row.isEmpty { representations.append(row) }
        }
        guard !representations.isEmpty else { return nil }
        // Handoff can deliver a photo as a temporary file, without PNG/TIFF
        // pasteboard data. Embed its pixels now: the temporary URL may expire.
        // Restrict this to a single remote raster photo; local Finder copies
        // and multiple-file selections retain their existing file semantics.
        if remote, representations.count == 1,
           let file = representations[0].first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }),
           let name = String(data: file.data, encoding: .utf8), let url = URL(string: name),
           url.isFileURL, ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(url.pathExtension.lowercased()) {
            // Read the URL through AppKit, which carries the pasteboard's
            // access grant. Reconstructing it from UTF-8 loses that grant.
            let granted = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first(where: { $0.standardizedFileURL == url.standardizedFileURL }) ?? url
            let accessing = granted.startAccessingSecurityScopedResource()
            defer { if accessing { granted.stopAccessingSecurityScopedResource() } }
            do {
                guard let png = try HandoffPhotoAccess.shared.withAccess(to: granted, operation: { try remotePhoto(granted) }) else { return nil }
                representations = [[.init(type: NSPasteboard.PasteboardType.png.rawValue, data: png)]]
            } catch {
                // macOS can deny its protected Handoff container even after
                // granting the pasteboard URL. Keep the file entry rather than
                // silently losing the user's copy. Never widen permissions.
                let failure = error as NSError
                let denied = (failure.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(failure.code)) ||
                    (failure.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(failure.code))
                guard denied else { throw error }
            }
        }
        let flat = representations.flatMap { $0 }
        // Do not ask AppKit to synthesize unadvertised representations of a
        // remote promise (including RTF converters that can stall termination).
        var text = remote ? (flat.first { $0.type == NSPasteboard.PasteboardType.string.rawValue || $0.type == NSPasteboard.PasteboardType.URL.rawValue }.flatMap { String(data: $0.data, encoding: .utf8) } ?? "") : (pb.string(forType: .string) ?? pb.string(forType: .URL) ?? "")
        let svg = flat.first { [SVGDocument.pasteboardType, "image/svg+xml"].contains($0.type) }
        if let svg { text = String(data: svg.data, encoding: .utf8) ?? String(data: svg.data, encoding: .utf16) ?? text }
        if text.isEmpty, let rtf = flat.first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue })?.data {
            text = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string ?? ""
        }
        let files = flat.filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }.compactMap { String(data: $0.data, encoding: .utf8) }.compactMap(URL.init(string:))
        if !files.isEmpty { text = files.map(\.path).joined(separator: "\n") }
        let kind = Clip.kind(for: text, hasImage: svg == nil && flat.contains { [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue].contains($0.type) }, hasFiles: !files.isEmpty)
        let title = files.isEmpty ? (text.isEmpty ? "Image copiée" : String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(90))) : files.map(\.lastPathComponent).joined(separator: ", ")
        var clip = Clip(title: title, text: text, source: remote ? "Autre appareil Apple" : source, sourceID: effectiveSourceID, kind: kind, fingerprint: "", payload: ClipPayload(representations: representations))
        clip.sourceURL = BrowserOrigin.metadata(items)
        return clip
    }

    static func remotePhoto(_ url: URL) throws -> Data? {
        // This runs on the remote import worker, never the main thread.
        // A file promised by Handoff may not have arrived yet: retry later.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .volumeIsLocalKey])
        guard values.isRegularFile == true, values.volumeIsLocal == true else {
            throw CaptureFailure.message("La photo reçue n’est pas un fichier local lisible.")
        }
        guard (values.fileSize ?? Int.max) <= limit else {
            throw CaptureFailure.message("Photo ignorée : elle dépasse 20 Mo.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard !data.isEmpty else { return nil }
        guard data.count <= limit else { throw CaptureFailure.message("Photo ignorée : elle dépasse 20 Mo.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              ["public.png", "public.jpeg", "public.heic", "public.heif", "public.tiff"].contains(type) else {
            throw CaptureFailure.message("La photo reçue ne peut pas être décodée.")
        }
        let size = try ImageRaster.dimensions(source)
        if type == "public.png" { return data }
        // Lossless PNG, full native resolution, with the photo's orientation.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(size.width, size.height)),
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) else { throw CaptureFailure.message("La photo reçue ne peut pas être décodée.") }
        let png = try CaptureImage.png(image)
        guard png.count <= limit else { throw CaptureFailure.message("La photo en pleine qualité dépasse 20 Mo.") }
        return png
    }

}

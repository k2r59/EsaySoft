import AppKit
import CryptoKit
import ImageIO

enum ClipKind:String,Codable,CaseIterable {
    case text,link,image,file,color,video
    var label:String {switch self {case .text:return "Textes";case .link:return "Liens";case .image:return "Images";case .file:return "Fichiers";case .color:return "Couleurs";case .video:return "Vidéos"}}
    var symbol:String {switch self {case .text:return "text.alignleft";case .link:return "link";case .image:return "photo";case .file:return "doc";case .color:return "paintpalette";case .video:return "video"}}
}
struct ClipRepresentation:Codable,Equatable {var type:String;var data:Data}
struct ClipPayload:Codable,Equatable {var representations:[[ClipRepresentation]]}
struct Clip:Codable,Identifiable {
    var id:UUID = UUID()
    var date = Date()
    var title:String
    var text:String
    var source:String
    var sourceID:String
    var kind:ClipKind
    var fingerprint:String
    var payload:ClipPayload
    var pinned=false
    var boards:[UUID]=[]
    var ocr=""
    var trashedAt:Date? = nil
    var storedBytes:Int? = nil
    var thumbnail:Data? = nil
    var parentID: UUID? = nil
    var duration: Double? = nil
    var sourceURL: String? = nil
    var imageMetadata: ClipImageMetadata? = nil
    var originURL: URL? { BrowserOrigin.url(sourceURL) }
    var durationLabel: String { let seconds = Int(max(0, duration ?? 0)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    var imageData: Data? { payload.representations.flatMap { $0 }.first { [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue].contains($0.type) }?.data }
    var editable: Bool { [.text, .link, .color].contains(kind) }
    // Metadata-only check: opening the preview loads the full payload on demand.
    var hasPreview: Bool { kind == .image || kind == .video || !text.isEmpty }
    var structuredFormat: StructuredFormat? { kind == .text ? StructuredHintCache.hint(text: text, fingerprint: fingerprint) : nil }
    var byteCount:Int {storedBytes ?? payload.representations.flatMap{$0}.reduce(0){$0+$1.data.count}}
    private static let imageCache:NSCache<NSString,NSImage> = {let c=NSCache<NSString,NSImage>();c.totalCostLimit=32*1024*1024;return c}()
    var image:NSImage? {
        let key=fingerprint as NSString
        if let hit=Self.imageCache.object(forKey:key){return hit}
        // Decode raster formats through ImageIO: an SVG mislabeled as PNG/TIFF
        // must not reach NSImage's automatic SVG decoder on the main process.
        guard let data=thumbnail ?? imageData, let source=CGImageSourceCreateWithData(data as CFData,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:640,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else{return nil}
        let image=NSImage(cgImage:cg,size:.zero)
        Self.imageCache.setObject(image,forKey:key,cost:640*640*4);return image
    }
    func metadata()->Clip {var c=self;c.storedBytes=byteCount;c.payload=ClipPayload(representations:[]);return c}
    func previewImage(maxPixels: Int) -> NSImage? {
        guard let data = imageData, let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
    mutating func prepareThumbnail() {
        prepareImageMetadata()
        guard kind == .image,thumbnail == nil,let data=payload.representations.flatMap({$0}).first(where:{[NSPasteboard.PasteboardType.png.rawValue,NSPasteboard.PasteboardType.tiff.rawValue].contains($0.type)})?.data,
              let source=CGImageSourceCreateWithData(data as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:640,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else{return}
        thumbnail=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])
    }
    /// Called on the import/storage worker. Never derive original dimensions
    /// from the 640px thumbnail, or decode image pixels just to show a label.
    mutating func prepareImageMetadata() {
        guard kind == .image, imageMetadata == nil, let data = imageData else { return }
        imageMetadata = ClipImageMetadata.read(data)
    }
    /// Presentation only: generated titles already repeat the start of text.
    /// Preserve real snippet titles and every byte used for copy/search/export.
    var cardTitle: String? {
        let head = Self.normalizedPreview(String(title.prefix(130)))
        guard !head.isEmpty else { return nil }
        if kind == .text || kind == .link || kind == .color {
            let body = Self.normalizedPreview(String(text.prefix(512)))
            if !body.isEmpty && body.hasPrefix(head) { return nil }
        }
        if kind == .image && ["image copiée", "capture d’écran", "capture d'ecran"].contains(head) { return nil }
        return title
    }
    private static func normalizedPreview(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    static func kind(for text:String,hasImage:Bool=false,hasFiles:Bool=false)->ClipKind {
        if hasFiles{return .file};if hasImage{return .image}
        let s=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if s.range(of:"^(?:#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|[0-9a-fA-F]{6})$",options:.regularExpression) != nil{return .color}
        if !s.contains(where:\.isWhitespace),let url=URL(string:s),["https","http","mailto"].contains(url.scheme?.lowercased() ?? ""){return .link}
        return .text
    }
    static func fingerprint(_ payload:ClipPayload)->String {
        var hash=SHA256()
        for item in payload.representations {hash.update(data:Data([0]));for r in item.sorted(by:{$0.type<$1.type}) {hash.update(data:Data(r.type.utf8));hash.update(data:Data([0]));hash.update(data:r.data)}}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    func matches(_ query:String)->Bool {query.split(whereSeparator:\.isWhitespace).allSatisfy {term in [title,text,source,ocr].contains{$0.localizedStandardContains(String(term))}}}
}
struct ClipImageMetadata: Codable, Equatable {
    let width: Int
    let height: Int
    let bytes: Int
    var dimensions: String { "\(width) × \(height) px" }
    var fileSize: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
    static func read(_ data: Data) -> Self? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= ImageRaster.pixelLimit / height else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? Self(width: height, height: width, bytes: data.count) : Self(width: width, height: height, bytes: data.count)
    }
}
struct Pinboard:Codable,Identifiable {var id=UUID();var name:String;var color:Int;var shared=false}
enum ClipboardPrivacy {
    static let forbidden:Set<String>=["org.nspasteboard.ConcealedType","org.nspasteboard.TransientType","org.nspasteboard.AutoGeneratedType","com.agilebits.onepassword","com.typeit4me.clipping"]
    static let excluded:Set<String>=["com.1password.1password","com.agilebits.onepassword7","com.bitwarden.desktop","com.apple.Passwords","com.apple.keychainaccess","org.keepassxc.keepassxc","com.dashlane.Dashlane","com.lastpass.LastPass"]
    static func allows(types:Set<String>,sourceID:String,extra:Set<String>)->Bool {types.isDisjoint(with:forbidden) && !excluded.contains(sourceID) && !extra.contains(sourceID)}
}

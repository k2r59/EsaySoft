import AppKit
import ImageIO
import SwiftUI

struct CaptureEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let date: Date
    var id: URL { url }
    var isVideo: Bool { ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) }
}

final class CapturePreview: @unchecked Sendable {
    let image: CGImage
    let originalWidth: Int
    let originalHeight: Int
    let fileSize: Int
    var memoryCost: Int { image.bytesPerRow * image.height }

    init(image: CGImage, width: Int, height: Int, fileSize: Int) {
        self.image = image
        originalWidth = width
        originalHeight = height
        self.fileSize = fileSize
    }
}

/// Serial background decoding avoids a burst of full-size images when the grid opens.
actor CaptureAssets {
    static let shared = CaptureAssets()
    private let previews = NSCache<NSString, CapturePreview>()

    init() {
        previews.totalCostLimit = 32 * 1024 * 1024
        previews.countLimit = 96
    }

    func list(in directory: URL) -> [CaptureEntry] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url -> CaptureEntry? in
            guard ["png", "jpg", "jpeg", "mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return CaptureEntry(url: url, date: values.creationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }

    func preview(for url: URL, maxPixelSize: Int = 640) -> CapturePreview? {
        guard !Task.isCancelled, maxPixelSize > 0 else { return nil }
        return autoreleasepool {
            var freshURL = url
            freshURL.removeAllCachedResourceValues()
            guard let values = try? freshURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            let key = "\(url.path)|\(maxPixelSize)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)" as NSString
            if let cached = previews.object(forKey: key) { return cached }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, 2048),
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            let result = CapturePreview(image: image,
                width: properties[kCGImagePropertyPixelWidth] as? Int ?? image.width,
                height: properties[kCGImagePropertyPixelHeight] as? Int ?? image.height,
                fileSize: values.fileSize ?? 0)
            previews.setObject(result, forKey: key, cost: result.memoryCost)
            return result
        }
    }
}

@MainActor final class CaptureLibrary: ObservableObject {
    @Published private(set) var entries: [CaptureEntry] = []
    private var refreshTask: Task<Void, Never>?

    func refresh(in directory: URL) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let entries = await CaptureAssets.shared.list(in: directory)
            guard !Task.isCancelled else { return }
            if self?.entries != entries { self?.entries = entries }
        }
    }

    deinit { refreshTask?.cancel() }
}

struct CaptureThumbnail: View {
    let entry: CaptureEntry
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit().padding(12)
            } else {
                Image(systemName: entry.isVideo ? "play.rectangle" : "photo")
                    .font(.system(size: 32)).foregroundStyle(Color.esAccent)
            }
        }.task(id: entry.id) {
            guard !entry.isVideo else { return }
            let preview = await CaptureAssets.shared.preview(for: entry.url)
            guard !Task.isCancelled else { return }
            thumbnail = preview.map { NSImage(cgImage: $0.image, size: .zero) }
        }
    }
}

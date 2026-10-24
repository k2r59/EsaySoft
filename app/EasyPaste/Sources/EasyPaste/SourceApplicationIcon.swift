import AppKit
import SwiftUI

/// A small, shared cache: no Launch Services lookup or icon decoding in a card's body.
/// Missing applications are cached briefly too, so an uninstalled source stays cheap.
@MainActor final class SourceIconCache {
    static let shared = SourceIconCache()
    private final class Entry: NSObject {
        let image: NSImage?
        let date = Date()
        init(_ image: NSImage?) { self.image = image }
    }
    private let entries = NSCache<NSString, Entry>()
    private var pending: [String: Task<NSImage?, Never>] = [:]
    private let resolver: (String) async -> NSImage?
    nonisolated private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "EasyPaste.source-icons"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    init(resolver: @escaping (String) async -> NSImage? = SourceIconCache.load) {
        self.resolver = resolver
        entries.countLimit = 128
        entries.totalCostLimit = 128 * 64 * 64 * 4
    }
    static func validIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 255 && id.contains(".") &&
        id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }
    }
    func cached(_ id: String) -> NSImage? { entries.object(forKey: id as NSString)?.image }
    func image(for id: String) async -> NSImage? {
        guard Self.validIdentifier(id) else { return nil }
        if let entry = entries.object(forKey: id as NSString), entry.image != nil || Date().timeIntervalSince(entry.date) < 60 {
            return entry.image
        }
        if let task = pending[id] { return await task.value }
        let resolve = resolver
        let task = Task { @MainActor [weak self] in
            let image = await resolve(id)
            self?.entries.setObject(Entry(image), forKey: id as NSString, cost: image == nil ? 1 : 64 * 64 * 4)
            self?.pending[id] = nil
            return image
        }
        pending[id] = task
        return await task.value
    }
    nonisolated private static func load(_ id: String) async -> NSImage? {
        await withCheckedContinuation { continuation in
            queue.addOperation {
                let image: NSImage? = autoreleasepool {
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    context.imageInterpolation = .high
                    icon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .copy, fraction: 1)
                    NSGraphicsContext.restoreGraphicsState()
                    guard let cg = bitmap.cgImage else { return nil }
                    return NSImage(cgImage: cg, size: NSSize(width: 32, height: 32))
                }
                continuation.resume(returning: image)
            }
        }
    }
}

@MainActor struct SourceApplicationIcon: View {
    let clip: Clip
    var size: CGFloat = 25
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let icon = image ?? SourceIconCache.shared.cached(clip.sourceID) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: clip.kind == .text ? "doc.text" : clip.kind.symbol)
                    .font(.system(size: size * 0.54, weight: .medium)).foregroundStyle(clip.kind.accent)
                    .frame(width: size, height: size)
                    .background(clip.kind.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.25))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
            .help("Copié depuis \(clip.source)")
            .task(id: clip.sourceID) {
                image = nil
                let loaded = await SourceIconCache.shared.image(for: clip.sourceID)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}

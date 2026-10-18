import AppKit
import SwiftUI
import ImageIO

enum ImageRaster {
    static let pixelLimit = 50_000_000

    static func dimensions(_ source: CGImageSource) throws -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= pixelLimit / height else {
            throw CaptureFailure.message("Cette image ne peut pas être ouverte (limite : 50 mégapixels).")
        }
        return CGSize(width: width, height: height)
    }

    static func decode(_ data: Data, maxPixels: Int? = nil) throws -> (CGImage, CGSize) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw CaptureFailure.message("Cette image ne peut pas être ouverte.")
        }
        let size = try dimensions(source)
        try Task.checkCancellation()
        let image: CGImage?
        if let maxPixels, maxPixels > 0, max(size.width, size.height) > CGFloat(maxPixels) {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        guard let image else { throw CaptureFailure.message("Cette image ne peut pas être décodée.") }
        try Task.checkCancellation()
        return (image, size)
    }

    static func fittedSize(pixels: CGSize, available: CGSize, displayScale: CGFloat) -> CGSize {
        let ratio = min(1 / max(1, displayScale), available.width / pixels.width, available.height / pixels.height)
        return CGSize(width: pixels.width * ratio, height: pixels.height * ratio)
    }
}

/// Fit uses a bounded decode; native pixels are decoded only on demand and
/// released on return to Fit. ImageIO never runs on the UI thread.
struct ImagePreview: View {
    let data: Data
    @Environment(\.displayScale) private var displayScale
    @State private var actualSize = false
    @State private var image: CGImage?
    @State private var pixels = CGSize.zero
    @State private var loading = true
    @State private var error = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(pixels == .zero ? "Image originale" : "\(Int(pixels.width)) × \(Int(pixels.height)) px")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted)
                Spacer()
                Button("Ajuster") { actualSize = false }.buttonStyle(PasteButtonStyle(primary: !actualSize))
                Button("100 %") { actualSize = true }.buttonStyle(PasteButtonStyle(primary: actualSize))
                    .help("Un pixel de l’image pour un pixel de l’écran")
            }
            GeometryReader { geo in
                ZStack {
                    if let image, !loading {
                        if actualSize {
                            ScrollView([.horizontal, .vertical]) {
                                Image(decorative: image, scale: displayScale).resizable().interpolation(.none)
                                    .frame(width: CGFloat(image.width)/displayScale, height: CGFloat(image.height)/displayScale)
                                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                            }
                        } else {
                            let size = ImageRaster.fittedSize(pixels: pixels, available: geo.size, displayScale: displayScale)
                            Image(decorative: image, scale: displayScale).resizable().interpolation(.high)
                                .frame(width: size.width, height: size.height)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    if loading { ProgressView("Chargement…") }
                    if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(.orange).padding() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: 360).background(Theme.bg).clipped()
        }.task(id: "\(actualSize)-\(displayScale)") {
            loading = true; image = nil; error = ""
            let limit: Int? = actualSize ? nil : Int(ceil(600 * displayScale))
            let worker = Task.detached(priority: .userInitiated) { try ImageRaster.decode(data, maxPixels: limit) }
            do {
                let decoded = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                image = decoded.0; pixels = decoded.1; loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

import AppKit

/// Reject empty/protected frames before they become a reference or an exported strip.
/// Work on a small raster; full-resolution pixels are never reduced in the export.
enum ScrollFrame {
    static func validate(_ image: CGImage) throws {
        let raster = try ScrollStitcher.Raster(image, width: min(256, image.width), height: min(256, image.height))
        let visible = stride(from: 0, to: raster.pixels.count, by: 4).contains {
            raster.pixels[$0 + 3] > 8 && max(raster.pixels[$0], raster.pixels[$0 + 1], raster.pixels[$0 + 2]) > 3
        }
        guard visible else {
            throw ScrollStitcher.failure("La zone capturée est noire ou vide. Vérifie que le contenu est visible et non protégé, puis clique sur Reprendre.")
        }
    }

    static func isStable(_ first: CGImage, _ next: CGImage) throws -> Bool {
        guard first.width == next.width, first.height == next.height else { return false }
        let width = min(160, first.width), height = min(280, first.height)
        let a = try ScrollStitcher.Raster(first, width: width, height: height)
        let b = try ScrollStitcher.Raster(next, width: width, height: height)
        return ScrollStitcher.difference(a, b, offset: 0) < 0.7
    }

    static func preview(_ image: CGImage) throws -> CGImage {
        let scale = min(1, 620 / Double(image.width), 360 / Double(image.height))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScrollStitcher.failure("Impossible de préparer l’aperçu.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw ScrollStitcher.failure("Aperçu indisponible.") }
        return result
    }
}

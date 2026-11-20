import AppKit
import SwiftUI
import ScreenCaptureKit

enum ScrollCaptureControlsLayout {
    static func frame(zone: CGRect, bounds: CGRect, size: CGSize) -> CGRect {
        let candidates = [
            CGPoint(x: zone.midX - size.width / 2, y: zone.minY - size.height - 12),
            CGPoint(x: zone.midX - size.width / 2, y: zone.maxY + 12),
            CGPoint(x: zone.maxX + 12, y: zone.midY - size.height / 2),
            CGPoint(x: zone.minX - size.width - 12, y: zone.midY - size.height / 2)
        ]
        return candidates.map { CGRect(origin: $0, size: size) }.first { bounds.contains($0) }
            ?? CGRect(x: bounds.midX - size.width / 2, y: bounds.minY + 16, width: size.width, height: size.height)
    }
}

enum ScrollCaptureVisibility {
    struct Window {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        var alpha: Double = 1
        var desktopOverlay = false
    }
    // macOS can scroll inactive windows, including on a secondary screen. Only
    // occlusion matters: do not capture an unrelated window covering the zone.
    static func permits(area: CGRect, source: CGWindowID, own: pid_t, windows: [Window]) -> Bool {
        for window in windows {
            if window.id == source { return window.bounds.contains(area) }
            if window.pid == own || window.alpha <= 0.01 || window.desktopOverlay { continue }
            let overlap = window.bounds.intersection(area)
            if !overlap.isNull && overlap.width > 1 && overlap.height > 1 { return false }
        }
        return false
    }
}

/// A narrow luminance raster preserves every vertical pixel while keeping the
/// overlap search bounded. The exported image always uses the original pixels.
struct ScrollRaster {
    static let columns = 48
    let width: Int
    let height: Int
    let pixels: [UInt8]
    init(_ image: CGImage) throws {
        let height = image.height
        width = image.width; self.height = height
        guard width >= 80, height >= 120, width <= ImageRaster.pixelLimit / height else {
            throw CaptureFailure.message("Sélectionne une zone de contenu d’au moins 80 × 120 pixels.")
        }
        var data = [UInt8](repeating: 0, count: Self.columns * height)
        let ok = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: Self.columns, height: height,
                bitsPerComponent: 8, bytesPerRow: Self.columns, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: Self.columns, height: height))
            return true
        }
        guard ok else { throw CaptureFailure.message("Impossible d’analyser la capture.") }
        pixels = data
    }
    func difference(_ next: ScrollRaster, offset: Int = 0, stride: Int = 1) -> Double {
        guard width == next.width, height == next.height else { return .infinity }
        let start = max(0, -offset), end = min(height, height - offset)
        var total = 0, count = 0
        for y in Swift.stride(from: start, to: end, by: stride) {
            // Exclude the scrollbar and thin selection outlines at either edge.
            for x in 3..<(Self.columns - 3) {
                total += abs(Int(pixels[(y + offset) * Self.columns + x]) - Int(next.pixels[y * Self.columns + x]))
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) : .infinity
    }
    /// Reject ambiguous/repeating or non-overlapping frames instead of silently
    /// producing a long image with missing or duplicated content.
    func downwardOffset(to next: ScrollRaster) -> Int? {
        guard width == next.width, height == next.height else { return nil }
        let limit = height - max(80, height / 4)
        guard limit >= 4 else { return nil }
        let rowStep = max(1, height / 70)
        var scores: [(Int, Double)] = []
        for offset in 4...limit { scores.append((offset, difference(next, offset: offset, stride: rowStep))) }
        scores.sort { $0.1 < $1.1 }
        guard let best = scores.first, best.1 < 1.8,
              let rival = scores.first(where: { abs($0.0 - best.0) > 3 }), rival.1 > best.1 + 0.45,
              difference(next, offset: best.0) < 1.8 else { return nil }
        return best.0
    }
}

actor ScrollAssembler {
    struct Update: Sendable {
        let sections: Int
        let width: Int
        let height: Int
        let message: String
        var limitReached = false
    }
    private var fragments: [CGImage] = []
    private var previous: ScrollRaster?
    private var candidate: ScrollRaster?
    private(set) var height = 0
    private var width = 0
    private let pixelLimit: Int
    init(pixelLimit: Int = ImageRaster.pixelLimit) { self.pixelLimit = pixelLimit }
    private func update(_ message: String, limit: Bool = false) -> Update {
        Update(sections: fragments.count, width: width, height: height, message: message, limitReached: limit)
    }
    func consume(_ image: CGImage) throws -> Update {
        try Task.checkCancellation()
        let next = try ScrollRaster(image)
        // Wait for two consecutive stable screenshots, including the first one.
        let stable = candidate.map { $0.difference(next, stride: 2) < 0.25 } ?? false
        candidate = next
        guard stable else { return update("Attends un instant après chaque mouvement…") }
        if let previous {
            if previous.difference(next, stride: 2) < 0.25 { return update("Fais défiler doucement vers le bas, puis marque une pause.") }
            guard let offset = previous.downwardOffset(to: next) else {
                return update("Raccord introuvable. Remonte au dernier passage, puis défile moins vite. Évite les en-têtes fixes.")
            }
            guard height + offset <= 30_000, width <= pixelLimit / (height + offset), fragments.count < 100 else {
                return update("Taille maximale atteinte. Termine pour conserver la capture.", limit: true)
            }
            guard let strip = image.cropping(to: CGRect(x: 0, y: image.height - offset, width: image.width, height: offset)) else {
                throw CaptureFailure.message("Impossible d’assembler ce passage.")
            }
            // Detach the strip from the full screenshot's backing allocation.
            let copy = try CaptureImage.composite([(strip, CGRect(x: 0, y: 0, width: strip.width, height: strip.height))], width: strip.width, height: strip.height)
            fragments.append(copy); height += offset; self.previous = next
        } else {
            guard image.width <= pixelLimit / image.height else { throw CaptureFailure.message("La capture dépasse les dimensions autorisées.") }
            fragments = [image]; width = image.width; height = image.height; previous = next
        }
        return update("Passage ajouté. Continue vers le bas ou termine.")
    }
    func finish() throws -> CGImage {
        guard !fragments.isEmpty else { throw CaptureFailure.message("Aucune image stable capturée. Réessaie en attendant avant de défiler.") }
        var top = 0
        let pieces: [(CGImage, CGRect)] = fragments.map { image in
            defer { top += image.height }
            return (image, CGRect(x: 0, y: height - top - image.height, width: width, height: image.height))
        }
        return try CaptureImage.composite(pieces, width: width, height: height)
    }
}

/// Reuse one ScreenCaptureKit filter and exclude EasyPaste's own controls.
@MainActor final class ScrollRegionCapture {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private let displayID: CGDirectDisplayID
    private let frame: CGRect
    init(area: CGRect, content: SCShareableContent) throws {
        guard let display = content.displays.first(where: { $0.frame.contains(area) }) else {
            throw CaptureFailure.message("Pour une capture défilante, sélectionne une zone sur un seul écran.")
        }
        displayID = display.displayID; frame = CGDisplayBounds(displayID)
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        guard !own.isEmpty else {
            throw CaptureFailure.message("Impossible d’exclure les commandes de la capture. Réessaie la capture défilante.")
        }
        filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let local = try CaptureImage.pixelAligned(area.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY), scale: CGFloat(filter.pointPixelScale))
        configuration = try CaptureImage.configuration(size: local.size, scale: CGFloat(filter.pointPixelScale))
        configuration.sourceRect = local
    }
    func image() async throws -> CGImage {
        guard CGDisplayIsActive(displayID) != 0, CGDisplayBounds(displayID) == frame else {
            throw CaptureFailure.message("La configuration des écrans a changé. Recommence la capture.")
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

@MainActor final class ScrollingCaptureModel: ObservableObject {
    @Published var message = "Préparation de la première image…"
    @Published var sections = 0
    @Published var dimensions = ""
    @Published var finishing = false
}

struct ScrollingCaptureControls: View {
    @ObservedObject var model: ScrollingCaptureModel
    let cancel: () -> Void
    let finish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Capture défilante", systemImage: "arrow.down.square").font(.headline)
                Spacer()
                if model.finishing { ProgressView().controlSize(.small) }
                else { Text("\(model.sections) passage(s)").font(.caption).foregroundStyle(Theme.muted) }
            }
            Text(model.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                .frame(height: 32, alignment: .topLeading)
            HStack {
                Text(model.dimensions).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                Spacer()
                Button("Annuler", action: cancel).buttonStyle(PasteButtonStyle())
                Button("Terminer", action: finish).buttonStyle(PasteButtonStyle(primary: true))
                    .disabled(model.sections == 0 || model.finishing)
            }
        }.padding(16).frame(width: 410).foregroundStyle(Theme.ink).chromeSurface(radius: 18)
    }
}

struct ScrollingCapturePreview: View {
    let image: CGImage
    let cancel: () -> Void
    let save: (Bool) -> Void
    @State private var saving = false
    private var previewWidth: CGFloat { min(560, CGFloat(image.width)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Capture défilante", systemImage: "arrow.down.square").font(.title2.bold())
            Text("\(image.width) × \(image.height) px · Vérifie les raccords avant d’enregistrer.").font(.caption).foregroundStyle(Theme.muted)
            ScrollView(.vertical) {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
                    .frame(width: previewWidth, height: previewWidth * CGFloat(image.height) / CGFloat(image.width))
            }.frame(width: previewWidth, height: min(430, previewWidth * CGFloat(image.height) / CGFloat(image.width)))
                .background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Annuler", action: cancel).buttonStyle(PasteButtonStyle())
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Annoter") { saving = true; save(true) }.buttonStyle(PasteButtonStyle()).disabled(saving)
                Button("Enregistrer et copier") { saving = true; save(false) }.buttonStyle(PasteButtonStyle(primary: true)).disabled(saving)
            }
        }.padding(22).foregroundStyle(Theme.ink).chromeSurface(radius: 22)
    }
}

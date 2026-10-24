import AppKit
import AVKit
import SwiftUI

/// The shelf keeps its bottom edge fixed while its preview grows upward.
struct ShelfLayout {
    static let previewAnimationDuration = 0.22
    let barHeight: CGFloat
    let previewHeight: CGFloat
    var height: CGFloat { barHeight + previewHeight }
    init(screenHeight: CGFloat, compact: Bool, expanded: Bool, footer: Bool = false) {
        let available = max(240, screenHeight - 24)
        barHeight = min((compact ? 270 : 320) + (footer ? 28 : 0), available)
        previewHeight = expanded ? min(600, max(0, available - barHeight)) : 0
    }
    static func previewWidth(in width: CGFloat) -> CGFloat {
        min(960, max(320, width * 0.495), max(0, width - 32))
    }
}

extension History {
    var shelfNeedsFooter: Bool { !recentlyTrashed.isEmpty || selection.count > 1 || !enabled }
}

/// A single silhouette: no overlapping windows or seam between the two parts.
struct ShelfOutline: InsettableShape {
    var previewHeight: CGFloat
    var previewWidth: CGFloat
    var insetAmount: CGFloat = 0
    func inset(by amount: CGFloat) -> ShelfOutline {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(previewHeight, previewWidth) }
        set { previewHeight = newValue.first; previewWidth = newValue.second }
    }
    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let top = min(max(0, previewHeight), max(0, bounds.height - 40))
        guard top > 1 else { return RoundedRectangle(cornerRadius: max(0, 36 - insetAmount)).path(in: rect) }
        let originalWidth = min(bounds.width, max(48, previewWidth))
        let gutter = (bounds.width - originalWidth) / 2
        guard gutter > 0 else { return RoundedRectangle(cornerRadius: max(0, min(36, bounds.width / 2, bounds.height / 2) - insetAmount)).path(in: rect) }
        let width = max(0, originalWidth - 2 * insetAmount)
        let left = rect.midX - width / 2, right = rect.midX + width / 2
        let y = rect.minY + top
        // Parallel contours keep their arc centres: an inset shrinks convex
        // radii and grows concave radii by the same amount.
        let originalRadius = min(36, top / 2, originalWidth / 2, gutter)
        let radius = max(0, originalRadius - insetAmount)
        let originalShoulder = min(58, top / 2, max(0, (bounds.width - originalWidth) / 2 - originalRadius))
        let shoulder = max(0, originalShoulder + insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: left + radius, y: rect.minY))
        p.addLine(to: CGPoint(x: right - radius, y: rect.minY))
        p.addArc(center: CGPoint(x: right - radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: right, y: y - shoulder))
        p.addArc(center: CGPoint(x: right + shoulder, y: y - shoulder), radius: shoulder, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: y))
        p.addArc(center: CGPoint(x: rect.maxX - radius, y: y + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: y + radius))
        p.addArc(center: CGPoint(x: rect.minX + radius, y: y + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: left - shoulder, y: y))
        p.addArc(center: CGPoint(x: left - shoulder, y: y - shoulder), radius: shoulder, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: left, y: rect.minY + radius))
        p.addArc(center: CGPoint(x: left + radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        // At the first animation frames (or exceptionally narrow stems), a
        // convex arc can collapse before the expanding concave arc. Trim that
        // short-lived degenerate contour to the inset bounds. Ordinary frames
        // keep the direct arc path and do not run a Boolean path operation.
        return insetAmount > originalRadius ? p.intersection(Path(rect)) : p
    }
}

struct ShelfRootView: View {
    @ObservedObject var history: History
    @AppStorage(GlassAppearance.key) private var glassTransparency = GlassAppearance.defaultTransparency
    @AppStorage(GlassTint.defaultsKey) private var storedGlassTint = GlassTint.blue.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    private var layout: ShelfLayout { ShelfLayout(screenHeight: history.shelfScreenHeight, compact: history.compact, expanded: history.shelfPreview != nil, footer: history.shelfNeedsFooter) }
    private var previewAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: ShelfLayout.previewAnimationDuration) }
    var body: some View {
        GeometryReader { geometry in
            let width = ShelfLayout.previewWidth(in: geometry.size.width)
            let shape = ShelfOutline(previewHeight: layout.previewHeight, previewWidth: width)
            ZStack(alignment: .bottom) {
                // Glass morphing must not capture or animate the shelf controls.
                // Its silhouette can grow while the bar stays in a fixed layer.
                surface(shape: shape)
                    .frame(width: geometry.size.width, height: layout.height)
                    .animation(previewAnimation, value: history.shelfPreview != nil)
                    .allowsHitTesting(false).accessibilityHidden(true)
                VStack(spacing: 0) {
                    if let clip = history.shelfPreview, layout.previewHeight > 0 {
                        ShelfPreviewView(history: history, clip: clip)
                            .id(clip.id).frame(width: width, height: layout.previewHeight).transition(.opacity)
                    }
                }
                .frame(width: geometry.size.width, height: layout.previewHeight, alignment: .bottom)
                .clipped()
                .animation(previewAnimation, value: history.shelfPreview != nil)
                .padding(.bottom, layout.barHeight)
                ShelfView(history: history, nativeGlassHosted: true).frame(height: layout.barHeight)
                    .background(alignment: .top) {
                        if history.shelfPreview != nil { ShelfGlassSeparator().frame(width: min(640, max(120, width - 80))) }
                    }
            }
            .frame(width: geometry.size.width, height: layout.height, alignment: .bottom)
            .contentShape(shape)
            // The transparent space retained during collapse is not interactive.
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
            .foregroundStyle(Theme.ink)
        }
        // AppKit reserves/releases window space synchronously. Inheriting that
        // geometry change into a SwiftUI animation makes the bar bounce. Only
        // the glass and the clipped preview above opt into animation.
        .transaction { $0.animation = nil }
        .onChange(of: history.selected) { _, _ in history.followShelfSelection() }
        .onChange(of: history.shelfNeedsFooter) { _, _ in history.resizeShelf?() }
        .onChange(of: history.visible.map { $0.id }) { _, _ in history.followShelfSelection() }
    }
    @ViewBuilder private func surface(shape: ShelfOutline) -> some View {
        if reduceTransparency || contrast == .increased {
            Color.clear.background(Theme.raised, in: shape)
                .overlay(shape.stroke(Theme.ink.opacity(0.45), lineWidth: 2).allowsHitTesting(false))
        } else if scheme == .dark {
            // Keep native material behind the readable wash. Applying clear
            // glass to the whole content can turn a dark, highly transparent
            // bar into a light plate while leaving its labels white.
            Color.clear.background {
                ZStack {
                    if #available(macOS 26.0, *) { Color.clear.glassEffect(.clear, in: shape) }
                    else { shape.fill(.regularMaterial).opacity(GlassAppearance.materialOpacity(glassTransparency)) }
                    Theme.bg.opacity(GlassAppearance.windowReadabilityOpacity(glassTransparency))
                    ShelfGlassWash(transparency: glassTransparency, tint: GlassTint.resolve(storedGlassTint))
                }.clipShape(shape)
            }.overlay { ShelfGlassRim(shape: shape) }
        } else if #available(macOS 26.0, *) {
            Color.clear
                .background { ShelfGlassWash(transparency: glassTransparency, tint: GlassTint.resolve(storedGlassTint)).clipShape(shape) }
                .glassEffect(.clear, in: shape)
                .overlay { ShelfGlassRim(shape: shape) }
        } else {
            Color.clear
                .background { ShelfGlassWash(transparency: glassTransparency, tint: GlassTint.resolve(storedGlassTint)).clipShape(shape) }
                .background { shape.fill(.regularMaterial).opacity(GlassAppearance.materialOpacity(glassTransparency)) }
                .overlay { ShelfGlassRim(shape: shape) }
        }
    }
}

@MainActor final class ShelfPreviewModel: ObservableObject {
    @Published private(set) var full: Clip?
    @Published private(set) var image: CGImage?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var result: StructuredResult?
    @Published private(set) var text = ""
    @Published private(set) var error = ""
    @Published private(set) var note = ""
    private var generation = 0

    func load(_ clip: Clip, history: History) async {
        reset()
        let token = generation
        do {
            let value = try await history.fullClip(clip)
            try Task.checkCancellation()
            guard token == generation else { return }
            if value.kind == .image {
                guard let data = value.imageData else { throw CocoaError(.fileReadCorruptFile) }
                let task = Task.detached(priority: .userInitiated) { try ImageRaster.decode(data, maxPixels: 2048).0 }
                let decoded = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                guard token == generation else { return }
                image = decoded
            } else if value.kind == .video {
                let url = try await history.videoURL(value)
                try Task.checkCancellation()
                guard token == generation else { return }
                player = AVPlayer(url: url)
            } else if value.kind == .text, let format = value.structuredFormat {
                let task = Task.detached(priority: .userInitiated) { try StructuredText.process(value.text, format: format) }
                do {
                    let parsed = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                    try Task.checkCancellation()
                    guard token == generation else { return }
                    result = parsed
                } catch is CancellationError { throw CancellationError() }
                catch { guard token == generation else { return }; note = error.localizedDescription }
            }
            try Task.checkCancellation()
            guard token == generation else { return }
            let displayed = result?.text ?? value.text
            text = StructuredText.prefix(displayed, bytes: StructuredText.displayLimit)
            if displayed.utf8.count > StructuredText.displayLimit { note = "Aperçu abrégé. La copie conserve le contenu complet." }
            full = value
        } catch is CancellationError { }
        catch { if token == generation { self.error = error.localizedDescription } }
    }
    func reset() {
        generation += 1
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        full = nil; image = nil; result = nil; text = ""; error = ""; note = ""
    }
}

struct ShelfPreviewView: View {
    @ThemePalette private var palette
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var history: History
    let clip: Clip
    @StateObject private var model = ShelfPreviewModel()
    private var pinned: Bool { history.clips.first { $0.id == clip.id }?.pinned ?? clip.pinned }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                SourceApplicationIcon(clip: clip, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.kind == .image ? "Capture d’écran" : clip.title).font(.system(size: 18, weight: .medium)).lineLimit(1)
                    if let metadata = clip.imageMetadata { Text("\(metadata.dimensions) · \(metadata.fileSize)").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }.padding(6).glassLabelPlate()
                Spacer(minLength: 12)
                Button { history.shelfPreview = nil } label: { Image(systemName: "chevron.down").font(.system(size: 16, weight: .medium)).frame(width: 42, height: 42).background(palette.controlPlate.opacity(0.95), in: RoundedRectangle(cornerRadius: 15)) }
                    .buttonStyle(FullAreaButtonStyle()).help("Replier l’aperçu · Échap").accessibilityLabel("Replier l’aperçu")
                Button { history.shelfPreview = nil } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).frame(width: 42, height: 42).background(palette.controlPlate.opacity(0.95), in: RoundedRectangle(cornerRadius: 15)) }
                    .buttonStyle(FullAreaButtonStyle()).help("Fermer l’aperçu").accessibilityLabel("Fermer l’aperçu")
            }
            GeometryReader { geometry in
                preview(height: geometry.size.height).frame(width: geometry.size.width, height: geometry.size.height)
            }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
            if !model.note.isEmpty { Text(model.note).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2).padding(5).glassLabelPlate() }
            HStack(spacing: 10) {
                if clip.kind == .image {
                    Button { history.annotate?(clip) } label: { Label("Annoter", systemImage: "pencil") }
                        .buttonStyle(ShelfActionButtonStyle()).help("Annoter").disabled(history.annotating || history.captureBusy)
                } else if clip.kind == .text, clip.structuredFormat != nil {
                    Button { history.openFormatter(clip) } label: { Label("Formater", systemImage: "curlybraces") }.buttonStyle(ShelfActionButtonStyle()).help("Formater")
                } else if clip.editable {
                    Button { history.editing = clip } label: { Label("Modifier", systemImage: "pencil") }.buttonStyle(ShelfActionButtonStyle()).help("Modifier")
                }
                Button { Task { _ = await history.copy([clip]) } } label: { Label("Copier", systemImage: "doc.on.doc") }.buttonStyle(ShelfActionButtonStyle()).help("Copier")
                Button { history.paste?([clip], false) } label: { Label("Coller", systemImage: "doc.on.clipboard") }.buttonStyle(ShelfActionButtonStyle(primary: true)).help("Coller")
                Button { history.togglePin(clip) } label: { Label(pinned ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: pinned ? "star.fill" : "star") }
                    .buttonStyle(ShelfActionButtonStyle()).help(pinned ? "Retirer des favoris" : "Ajouter aux favoris")
                    .accessibilityAddTraits(pinned ? .isSelected : [])
                Button { history.requestTrash([clip]) } label: { Label("Mettre à la corbeille", systemImage: "trash").foregroundStyle(Theme.danger) }
                    .buttonStyle(ShelfActionButtonStyle()).help("Mettre à la corbeille").padding(.leading, 4)
            }.labelStyle(.iconOnly).disabled(model.full == nil)
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20)
            .task(id: clip.fingerprint) { await model.load(clip, history: history) }
            .onDisappear { model.reset() }
    }
    @ViewBuilder private func preview(height: CGFloat) -> some View {
        if let full = model.full {
            if let image = model.image {
                GeometryReader { geometry in
                    let available = CGSize(width: max(0, geometry.size.width - 16), height: max(0, geometry.size.height - 16))
                    let size = ImageRaster.fittedSize(pixels: CGSize(width: image.width, height: image.height), available: available, displayScale: displayScale)
                    Image(decorative: image, scale: displayScale).resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(8)
                }
            } else if let player = model.player {
                VideoPreview(player: player, imageHeight: max(40, height - 56)).padding(8)
            } else if let document = model.result?.markdown {
                MarkdownPreviewView(document: document, revision: 0, findRequest: 0)
            } else if let document = model.result?.svg {
                SVGPreviewView(document: document, history: history)
            } else if full.kind == .file, let path = full.text.split(separator: "\n").first {
                if SVGFile.isSVG(String(path)) { SVGFilePreview(url: URL(fileURLWithPath: String(path)), history: history, height: height) }
                else { FilePreview(url: URL(fileURLWithPath: String(path))) }
            } else {
                ShelfTextPreview(text: model.text, monospaced: full.structuredFormat != nil)
            }
        } else if !model.error.isEmpty {
            VStack(spacing: 12) { Image(systemName: "exclamationmark.triangle"); Text(model.error).font(.system(size: 13)).multilineTextAlignment(.center) }.foregroundStyle(Theme.warning).padding(24)
        } else { ProgressView("Chargement de l’aperçu…").frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
}

/// TextKit lays out only the visible part, even for a large clipboard item.
private struct ShelfTextPreview: NSViewRepresentable {
    let text: String
    let monospaced: Bool
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WrappingScrollView(), view = NSTextView()
        scroll.hasVerticalScroller = true; scroll.documentView = view
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.autoresizingMask = [.width]; view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true; view.textContainerInset = NSSize(width: 20, height: 20)
        view.layoutManager?.allowsNonContiguousLayout = true
        view.setAccessibilityLabel("Contenu de l’aperçu")
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
        view.font = monospaced ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 15)
        view.textColor = NSColor(Theme.ink); view.backgroundColor = NSColor(Theme.panel)
        scroll.tile()
    }
}

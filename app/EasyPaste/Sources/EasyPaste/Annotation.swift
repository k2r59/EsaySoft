import AppKit
import SwiftUI
import ImageIO
import CoreText

enum AnnotationTool: String, CaseIterable {
    case arrow, rectangle, text, highlight, redact, crop
    var title: String { switch self { case .arrow: "Flèche"; case .rectangle: "Cadre"; case .text: "Texte"; case .highlight: "Surligner"; case .redact: "Masquer"; case .crop: "Recadrer" } }
    var icon: String { switch self { case .arrow: "arrow.up.right"; case .rectangle: "rectangle"; case .text: "textformat"; case .highlight: "highlighter"; case .redact: "square.fill"; case .crop: "crop" } }
}
enum AnnotationColor: Int, CaseIterable {
    case coral, mint, blue, yellow, white, black
    var rgba: [CGFloat] { switch self { case .coral: [1,0.35,0.30,1]; case .mint: [0.61,0.97,0.8,1]; case .blue: [0.31,0.61,1,1]; case .yellow: [1,0.85,0.22,1]; case .white: [1,1,1,1]; case .black: [0.035,0.04,0.05,1] } }
    var cgColor: CGColor { CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: rgba)! }
    var title: String { ["Corail", "Menthe", "Bleu", "Jaune", "Blanc", "Noir"][rawValue] }
}
struct AnnotationMark {
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var color: AnnotationColor
    var width: CGFloat
    var text = ""
    var rect: CGRect { CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y)) }
}
struct AnnotationSnapshot {
    var marks: [AnnotationMark] = []
    var crop: CGRect?
}
enum AnnotationRenderer {
    static func draw(_ marks: [AnnotationMark], in context: CGContext, size: CGSize) {
        for mark in marks {
            context.saveGState()
            let start = CGPoint(x: mark.start.x, y: size.height - mark.start.y)
            let end = CGPoint(x: mark.end.x, y: size.height - mark.end.y)
            let rect = CGRect(x: mark.rect.minX, y: size.height - mark.rect.maxY, width: mark.rect.width, height: mark.rect.height)
            context.setStrokeColor(mark.color.cgColor); context.setFillColor(mark.color.cgColor)
            context.setLineWidth(mark.width); context.setLineCap(.round); context.setLineJoin(.round)
            switch mark.tool {
            case .arrow:
                context.move(to: start); context.addLine(to: end); context.strokePath()
                let angle = atan2(end.y-start.y, end.x-start.x), length = max(mark.width*4, 12)
                context.move(to: CGPoint(x: end.x-length*cos(angle-0.5), y: end.y-length*sin(angle-0.5)))
                context.addLine(to: end)
                context.addLine(to: CGPoint(x: end.x-length*cos(angle+0.5), y: end.y-length*sin(angle+0.5)))
                context.strokePath()
            case .rectangle: context.stroke(rect)
            case .highlight: context.setAlpha(0.3); context.fill(rect)
            case .redact:
                // Opaque pixels, never blur: the original content cannot be reconstructed from the export.
                context.setAlpha(1); context.setBlendMode(.copy); context.setFillColor(AnnotationColor.black.cgColor); context.fill(rect.integral)
            case .text:
                let font = CTFontCreateWithName("Helvetica-Bold" as CFString, max(14, mark.width*6), nil)
                let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): mark.color.cgColor]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: mark.text, attributes: attrs))
                context.textMatrix = .identity; context.textPosition = CGPoint(x: start.x, y: start.y-CTFontGetAscent(font))
                CTLineDraw(line, context)
            case .crop: break
            }
            context.restoreGState()
        }
    }
    static func export(data: Data, snapshot: AnnotationSnapshot) throws -> Data {
        let (image, size) = try ImageRaster.decode(data)
        var result = image
        if !snapshot.marks.isEmpty {
            let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureFailure.message("Impossible de créer la copie.") }
            context.interpolationQuality = .none
            context.setBlendMode(.copy); context.draw(image, in: CGRect(origin: .zero, size: size)); context.setBlendMode(.normal)
            draw(snapshot.marks, in: context, size: size)
            guard let annotated = context.makeImage() else { throw CaptureFailure.message("Impossible de créer la copie.") }
            result = annotated
        }
        if let crop = snapshot.crop {
            let area = crop.integral.intersection(CGRect(origin: .zero, size: size))
            guard area.width >= 2, area.height >= 2, let cropped = result.cropping(to: area) else { throw CaptureFailure.message("La zone de recadrage est trop petite.") }
            result = cropped
        }
        return try CaptureImage.png(result)
    }
}
@MainActor final class AnnotationModel: ObservableObject {
    let data: Data
    let image: CGImage
    let size: CGSize
    @Published var tool: AnnotationTool = .arrow
    @Published var color: AnnotationColor = .coral
    @Published var width: CGFloat = 4
    @Published var snapshot = AnnotationSnapshot()
    @Published var draft: AnnotationMark?
    @Published var text = ""
    @Published var textPoint: CGPoint?
    @Published var saving = false
    @Published var error = ""
    @Published private(set) var undoStates: [AnnotationSnapshot] = []
    @Published private(set) var redoStates: [AnnotationSnapshot] = []
    var dirty: Bool { !snapshot.marks.isEmpty || snapshot.crop != nil || textPoint != nil }
    init(data: Data, image: CGImage, size: CGSize) { self.data = data; self.image = image; self.size = size }
    nonisolated static func prepare(_ data: Data) throws -> (CGImage, CGSize) {
        try ImageRaster.decode(data, maxPixels: 2000)
    }
    func commit(_ mark: AnnotationMark) {
        guard !saving else { return }
        undoStates.append(snapshot); redoStates.removeAll()
        if mark.tool == .crop { snapshot.crop = mark.rect.intersection(CGRect(origin: .zero, size: size)) }
        else { snapshot.marks.append(mark) }
        draft = nil
    }
    func addText() {
        guard let point = textPoint, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        commit(AnnotationMark(tool: .text, start: point, end: point, color: color, width: width*max(size.width,size.height)/900, text: String(text.prefix(400))))
        textPoint = nil; text = ""
    }
    func undo() { guard !saving, let previous = undoStates.popLast() else { return }; redoStates.append(snapshot); snapshot = previous; draft = nil }
    func redo() { guard !saving, let next = redoStates.popLast() else { return }; undoStates.append(snapshot); snapshot = next; draft = nil }
}
struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var model: AnnotationModel
    func makeNSView(context: Context) -> AnnotationCanvasView { AnnotationCanvasView(model: model) }
    func updateNSView(_ view: AnnotationCanvasView, context: Context) { view.needsDisplay = true }
}
@MainActor final class AnnotationCanvasView: NSView {
    let model: AnnotationModel
    private var anchor: CGPoint?
    init(model: AnnotationModel) { self.model = model; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    var imageRect: CGRect {
        let size = ImageRaster.fittedSize(pixels: model.size, available: CGSize(width: max(1,bounds.width-40), height: max(1,bounds.height-40)), displayScale: window?.backingScaleFactor ?? 1)
        let scale = window?.backingScaleFactor ?? 1
        return CGRect(x: (((bounds.width-size.width)/2)*scale).rounded()/scale, y: (((bounds.height-size.height)/2)*scale).rounded()/scale, width: size.width, height: size.height)
    }
    func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), rect = imageRect
        return CGPoint(x: min(model.size.width,max(0,(p.x-rect.minX)/rect.width*model.size.width)), y: min(model.size.height,max(0,(rect.maxY-p.y)/rect.height*model.size.height)))
    }
    override func resetCursorRects() { addCursorRect(imageRect, cursor: model.tool == .text ? .iBeam : .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect, ratio = rect.width / model.size.width
        cg.setFillColor(CGColor(gray: 0.035, alpha: 1)); cg.fill(bounds)
        cg.interpolationQuality = .high
        cg.saveGState(); cg.translateBy(x: rect.minX, y: rect.minY); cg.scaleBy(x: ratio, y: ratio)
        cg.draw(model.image, in: CGRect(origin: .zero, size: model.size))
        AnnotationRenderer.draw(model.snapshot.marks + (model.draft.map { [$0] } ?? []), in: cg, size: model.size)
        if let crop = model.draft?.tool == .crop ? model.draft?.rect : model.snapshot.crop {
            let region = CGRect(x: crop.minX, y: model.size.height-crop.maxY, width: crop.width, height: crop.height)
            cg.saveGState(); cg.addRect(CGRect(origin: .zero, size: model.size)); cg.addRect(region); cg.clip(using: .evenOdd)
            cg.setFillColor(CGColor(gray: 0, alpha: 0.6)); cg.fill(CGRect(origin: .zero, size: model.size)); cg.restoreGState()
            cg.setStrokeColor(AnnotationColor.mint.cgColor); cg.setLineWidth(1.5/ratio); cg.setLineDash(phase: 0, lengths: [6/ratio,4/ratio]); cg.stroke(region)
        }
        cg.restoreGState()
    }
    override func mouseDown(with event: NSEvent) {
        guard !model.saving, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        if model.textPoint != nil { model.addText() }
        let point = imagePoint(event)
        if model.tool == .text { model.textPoint = point; return }
        anchor = point
        model.draft = AnnotationMark(tool: model.tool, start: point, end: point, color: model.color, width: model.width*max(model.size.width,model.size.height)/900)
    }
    override func mouseDragged(with event: NSEvent) { guard anchor != nil, !model.saving else { return }; model.draft?.end = imagePoint(event) }
    override func mouseUp(with event: NSEvent) {
        guard anchor != nil, var mark = model.draft else { return }; anchor = nil; mark.end = imagePoint(event)
        let distance = hypot(mark.end.x-mark.start.x, mark.end.y-mark.start.y)
        if distance > 3 && (mark.tool == .arrow || (mark.rect.width >= 2 && mark.rect.height >= 2)) { model.commit(mark) } else { model.draft = nil }
    }
}
struct AnnotationView: View {
    @ObservedObject var model: AnnotationModel
    let cancel: () -> Void
    let save: () -> Void
    @FocusState private var textFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                BrandMark(size: 28)
                VStack(alignment: .leading, spacing: 4) { Text("Annoter la capture").font(.system(size: 18, weight: .semibold)); Text("Une copie à ta façon. L’original reste intact.").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Spacer(); Button("Annuler", action: cancel).buttonStyle(PasteButtonStyle()).disabled(model.saving)
                Button(action: save) { HStack(spacing: 8) { if model.saving { ProgressView().controlSize(.small) }; Text(model.saving ? "Création…" : "Créer une copie") } }.buttonStyle(PasteButtonStyle(primary: true)).disabled(model.saving || !model.dirty).keyboardShortcut("s", modifiers: .command)
            }.padding(20)
            HStack(spacing: 5) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Button { model.tool = tool } label: { VStack(spacing: 5) { Image(systemName: tool.icon).font(.system(size: 15)); Text(tool.title).font(.system(size: 10)) }.frame(width: 60, height: 43).foregroundStyle(model.tool == tool ? Theme.bg : Theme.ink).background(model.tool == tool ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(FullAreaButtonStyle()).help(tool.title).accessibilityLabel(tool.title)
                }
                Divider().frame(height: 28).padding(.horizontal, 7)
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button { model.color = color } label: { Circle().fill(Color(cgColor: color.cgColor)).frame(width: 17, height: 17).padding(4).overlay(Circle().strokeBorder(model.color == color ? .white : .clear, lineWidth: 1.5)) }.buttonStyle(FullAreaButtonStyle()).help(color.title).accessibilityLabel(color.title)
                }
                Spacer(minLength: 5)
                Menu { ForEach([CGFloat(2),4,7], id: \.self) { value in Button(value == 2 ? "Trait fin" : value == 4 ? "Trait moyen" : "Trait épais") { model.width = value } } } label: { Image(systemName: "lineweight").frame(width: 24, height: 24).contentShape(.interaction, Rectangle()) }.menuStyle(.borderlessButton).fixedSize().help("Épaisseur du trait")
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 24, height: 24) }.disabled(model.undoStates.isEmpty).keyboardShortcut("z", modifiers: .command).help("Annuler · ⌘Z")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 24, height: 24) }.disabled(model.redoStates.isEmpty).keyboardShortcut("z", modifiers: [.command,.shift]).help("Rétablir · ⇧⌘Z")
            }.buttonStyle(FullAreaButtonStyle()).padding(.horizontal, 18).padding(.vertical, 10).background(Theme.panel).disabled(model.saving)
            if model.textPoint != nil {
                HStack { Image(systemName: "textformat"); TextField("Ton texte…", text: $model.text).textFieldStyle(.plain).focused($textFocused).onSubmit { model.addText() }; Button("Ajouter") { model.addText() }.buttonStyle(PasteButtonStyle(primary: true)); Button("Annuler") { model.textPoint = nil; model.text = "" }.buttonStyle(FullAreaButtonStyle()) }.padding(12).background(Theme.raised).task { await Task.yield(); textFocused = true }
            }
            AnnotationCanvas(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(model.error.isEmpty ? (model.tool == .redact ? "Masquage opaque · le texte couvert est supprimé de la copie." : model.tool == .crop ? "Dessine la zone à conserver. Les annotations restent modifiables avec Annuler." : "Glisse sur l’image · ⌘Z pour annuler") : model.error).lineLimit(2).foregroundStyle(model.error.isEmpty ? Theme.muted : .orange)
                Spacer(); Text("\(Int(model.size.width)) × \(Int(model.size.height)) px").monospacedDigit().foregroundStyle(Theme.muted)
            }.font(.system(size: 11)).padding(14)
        }.background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
}
@MainActor final class AnnotationController: NSObject, NSWindowDelegate {
    private let history: History
    private var window: NSPanel?
    private var model: AnnotationModel?
    private var clip: Clip?
    var onSaved: (() -> Void)?
    init(history: History) { self.history = history }
    func open(_ clip: Clip) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        guard !history.annotating else { return }; history.annotating = true
        Task { [self] in
            do {
                let full = try await history.fullClip(clip)
                guard let data = full.imageData else { throw CaptureFailure.message("Image introuvable.") }
                let prepared = try await Task.detached(priority: .userInitiated) { try AnnotationModel.prepare(data) }.value
                let model = AnnotationModel(data: data, image: prepared.0, size: prepared.1)
                self.model = model; self.clip = clip
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { throw CaptureFailure.message("Aucun écran disponible.") }
                let frame = screen.visibleFrame
                let width = min(1020, frame.width-40), height = min(700, frame.height-55)
                let panel = NSPanel(contentRect: CGRect(x: frame.midX-width/2, y: frame.midY-height/2, width: width, height: height), styleMask: [.titled,.closable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
                panel.title = "Annoter la capture"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.isReleasedWhenClosed = false
                panel.minSize = CGSize(width: 850, height: 420); panel.level = .floating; panel.delegate = self; panel.backgroundColor = NSColor(Theme.bg)
                panel.contentView = NSHostingView(rootView: AnnotationView(model: model, cancel: { [weak self] in self?.requestClose() }, save: { [weak self] in self?.save() }).padding(.top, 20).background(Theme.bg))
                window = panel; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            } catch { history.annotating = false; history.report(error.localizedDescription) }
        }
    }
    func requestClose() { if canClose() { close() } }
    private func canClose() -> Bool {
        guard model?.saving != true else { return false }
        guard model?.dirty == true else { return true }
        let alert = NSAlert(); alert.messageText = "Abandonner les annotations ?"; alert.informativeText = "L’original reste dans ton historique. Cette copie n’a pas encore été créée."; alert.addButton(withTitle: "Continuer à modifier"); alert.addButton(withTitle: "Abandonner")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if canClose() { close() }; return false }
    private func close() { window?.orderOut(nil); window = nil; model = nil; clip = nil; history.annotating = false }
    private func save() {
        guard let model, let clip, !model.saving else { return }
        if model.textPoint != nil { model.addText() }
        model.saving = true; model.error = ""
        let data = model.data, snapshot = model.snapshot
        Task {
            do {
                let png = try await Task.detached(priority: .userInitiated) { try AnnotationRenderer.export(data: data, snapshot: snapshot) }.value
                let saved = try await history.saveImage(png, parent: clip)
                let copied = await history.copy([saved]); close(); onSaved?()
                history.report(copied ? "Copie modifiée créée · prête à coller avec ⌘V." : "Copie modifiée créée. Utilise Copier pour la préparer.")
            } catch { model.saving = false; model.error = error.localizedDescription }
        }
    }
}

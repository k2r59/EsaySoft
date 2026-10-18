import AppKit
import SwiftUI
import CoreText

enum AnnotationTool: String, CaseIterable {
    case selection, arrow, text, rectangle, highlight, pencil, redact, crop
    var title: String { switch self { case .selection: "Sélection"; case .arrow: "Flèche"; case .rectangle: "Rectangle"; case .text: "Texte"; case .highlight: "Surligner"; case .pencil: "Crayon"; case .redact: "Masquer"; case .crop: "Recadrer" } }
    var icon: String { switch self { case .selection: "cursorarrow"; case .arrow: "arrow.up.right"; case .rectangle: "rectangle"; case .text: "textformat"; case .highlight: "highlighter"; case .pencil: "pencil.tip"; case .redact: "square.lefthalf.filled"; case .crop: "crop" } }
}
enum AnnotationColor: Int, CaseIterable {
    case coral, mint, blue, yellow, white, black
    var rgba: [CGFloat] { switch self { case .coral: [1,0.47,0.43,1]; case .mint: [0.61,0.97,0.8,1]; case .blue: [0.71,0.68,1,1]; case .yellow: [1,0.85,0.22,1]; case .white: [1,1,1,1]; case .black: [0.035,0.04,0.05,1] } }
    var cgColor: CGColor { CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: rgba)! }
    var title: String { ["Corail", "Menthe", "Lavande", "Jaune", "Blanc", "Noir"][rawValue] }
}
enum AnnotationArrowhead: String, CaseIterable {
    case open, filled, dot
    var title: String { switch self { case .open: "Pointe ouverte"; case .filled: "Pointe pleine"; case .dot: "Point" } }
    var icon: String { switch self { case .open: "arrow.right"; case .filled: "arrowtriangle.right.fill"; case .dot: "circle.fill" } }
}
struct AnnotationMark: Identifiable, Equatable {
    var id = UUID()
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var color: AnnotationColor
    var width: CGFloat
    var text = ""
    var points: [CGPoint] = []
    var arrowhead: AnnotationArrowhead = .open
    var rect: CGRect { CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y)) }
    var bounds: CGRect {
        if tool == .text {
            let font = NSFont.boldSystemFont(ofSize: max(14, width*6))
            let size = (text as NSString).size(withAttributes: [.font: font])
            return CGRect(origin: start, size: CGSize(width: max(8, size.width), height: max(14, size.height)))
        }
        if tool == .pencil, let first = points.first {
            return points.reduce(CGRect(origin: first, size: CGSize(width: 0.1, height: 0.1))) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.1, height: 0.1))) }
        }
        return rect
    }
    func translated(by delta: CGSize, within size: CGSize) -> Self {
        let box = bounds
        let dx = min(max(delta.width, -box.minX), max(0, size.width-box.maxX))
        let dy = min(max(delta.height, -box.minY), max(0, size.height-box.maxY))
        var copy = self
        copy.start.x += dx; copy.start.y += dy; copy.end.x += dx; copy.end.y += dy
        copy.points = points.map { CGPoint(x: $0.x+dx, y: $0.y+dy) }
        return copy
    }
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if tool == .arrow { return Self.distance(point, to: start, end) <= max(tolerance, width) }
        if tool == .pencil {
            return zip(points, points.dropFirst()).contains { Self.distance(point, to: $0.0, $0.1) <= max(tolerance, width) }
        }
        let outer = bounds.insetBy(dx: -tolerance, dy: -tolerance)
        guard outer.contains(point) else { return false }
        if tool == .rectangle { return !bounds.insetBy(dx: tolerance, dy: tolerance).contains(point) }
        return true
    }
    private static func distance(_ p: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
        let t = length > 0 ? min(1, max(0, ((p.x-a.x)*dx+(p.y-a.y)*dy)/length)) : 0
        return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
    }
}
struct AnnotationSnapshot: Equatable {
    var marks: [AnnotationMark] = []
    var crop: CGRect?
}
enum AnnotationRenderer {
    static func draw(_ marks: [AnnotationMark], in context: CGContext, size: CGSize) {
        for mark in marks {
            context.saveGState()
            let start = CGPoint(x: mark.start.x, y: size.height-mark.start.y)
            let end = CGPoint(x: mark.end.x, y: size.height-mark.end.y)
            let rect = CGRect(x: mark.rect.minX, y: size.height-mark.rect.maxY, width: mark.rect.width, height: mark.rect.height)
            context.setStrokeColor(mark.color.cgColor); context.setFillColor(mark.color.cgColor)
            context.setLineWidth(mark.width); context.setLineCap(.round); context.setLineJoin(.round)
            switch mark.tool {
            case .arrow:
                context.move(to: start); context.addLine(to: end); context.strokePath()
                let angle = atan2(end.y-start.y, end.x-start.x), length = max(mark.width*4, 12)
                let a = CGPoint(x: end.x-length*cos(angle-0.5), y: end.y-length*sin(angle-0.5))
                let b = CGPoint(x: end.x-length*cos(angle+0.5), y: end.y-length*sin(angle+0.5))
                if mark.arrowhead == .dot { context.fillEllipse(in: CGRect(x: end.x-mark.width*1.6, y: end.y-mark.width*1.6, width: mark.width*3.2, height: mark.width*3.2)) }
                else {
                    context.move(to: a); context.addLine(to: end); context.addLine(to: b)
                    if mark.arrowhead == .filled { context.closePath(); context.fillPath() } else { context.strokePath() }
                }
            case .rectangle:
                context.addPath(CGPath(roundedRect: rect, cornerWidth: min(12, rect.width/4), cornerHeight: min(12, rect.height/4), transform: nil)); context.strokePath()
            case .pencil:
                if let first = mark.points.first {
                    context.move(to: CGPoint(x: first.x, y: size.height-first.y))
                    for p in mark.points.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: size.height-p.y)) }
                    context.strokePath()
                }
            case .highlight: context.setAlpha(0.3); context.fill(rect)
            case .redact:
                context.setAlpha(1); context.setBlendMode(.copy); context.setFillColor(AnnotationColor.black.cgColor); context.fill(rect.integral)
            case .text:
                let font = CTFontCreateWithName("Helvetica-Bold" as CFString, max(14, mark.width*6), nil)
                let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): mark.color.cgColor]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: mark.text, attributes: attrs))
                context.textMatrix = .identity; context.textPosition = CGPoint(x: start.x, y: start.y-CTFontGetAscent(font)); CTLineDraw(line, context)
            case .crop, .selection: break
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
            guard let annotated = context.makeImage() else { throw CaptureFailure.message("Impossible de créer la copie.") }; result = annotated
        }
        if let crop = snapshot.crop {
            let area = crop.integral.intersection(CGRect(origin: .zero, size: size))
            guard area.width >= 2, area.height >= 2, let cropped = result.cropping(to: area) else { throw CaptureFailure.message("La zone de recadrage est trop petite.") }; result = cropped
        }
        return try CaptureImage.png(result)
    }
}

@MainActor final class AnnotationModel: ObservableObject {
    let data: Data
    let image: CGImage
    let size: CGSize
    @Published var nativeImage: CGImage?
    @Published var loadingNative = false
    @Published var tool: AnnotationTool = .arrow
    @Published var color: AnnotationColor = .coral
    @Published var width: CGFloat = 4
    @Published var arrowhead: AnnotationArrowhead = .filled
    @Published var snapshot = AnnotationSnapshot()
    // Pointer motion only invalidates the AppKit canvas, not the SwiftUI sidebar.
    var draft: AnnotationMark?
    @Published var selectedID: UUID?
    @Published var zoom: CGFloat?
    @Published var text = ""
    @Published var textPoint: CGPoint?
    @Published var editingTextID: UUID?
    @Published var saving = false
    @Published var replaceOriginal = false
    @Published var copyToClipboard = true
    @Published var error = ""
    @Published private(set) var undoStates: [AnnotationSnapshot] = []
    @Published private(set) var redoStates: [AnnotationSnapshot] = []
    private var styleBase: AnnotationSnapshot?
    var dirty: Bool { !snapshot.marks.isEmpty || snapshot.crop != nil || textPoint != nil }
    var selectedMark: AnnotationMark? { snapshot.marks.first { $0.id == selectedID } }
    var activeTool: AnnotationTool { selectedMark?.tool ?? tool }
    var renderedMarks: [AnnotationMark] {
        guard let draft, draft.tool != .crop else { return snapshot.marks }
        if snapshot.marks.contains(where: { $0.id == draft.id }) { return snapshot.marks.map { $0.id == draft.id ? draft : $0 } }
        return snapshot.marks + [draft]
    }
    init(data: Data, image: CGImage, size: CGSize) {
        self.data = data; self.image = image; self.size = size
        width = min(48, max(4, (max(size.width, size.height)/900*4).rounded()))
    }
    nonisolated static func prepare(_ data: Data) throws -> (CGImage, CGSize) { try ImageRaster.decode(data, maxPixels: 4096) }
    private func checkpoint(_ previous: AnnotationSnapshot) {
        undoStates.append(previous)
        if undoStates.count > 100 { undoStates.removeFirst(undoStates.count-100) }
        redoStates.removeAll()
    }
    func chooseTool(_ value: AnnotationTool) {
        guard !saving else { return }
        if textPoint != nil { addText(); textPoint = nil; text = ""; editingTextID = nil }
        draft = nil; selectedID = nil; tool = value
    }
    func select(_ id: UUID?) {
        guard !saving else { return }; selectedID = id; tool = .selection; draft = nil
        if let mark = selectedMark { color = mark.color; width = mark.width; arrowhead = mark.arrowhead }
    }
    func commit(_ mark: AnnotationMark) {
        guard !saving, mark.tool != .selection else { return }
        checkpoint(snapshot)
        if mark.tool == .crop { snapshot.crop = mark.rect.intersection(CGRect(origin: .zero, size: size)); selectedID = nil }
        else { snapshot.marks.append(mark); selectedID = mark.id }
        draft = nil
    }
    func replace(_ mark: AnnotationMark) {
        guard !saving, let i = snapshot.marks.firstIndex(where: { $0.id == mark.id }), snapshot.marks[i] != mark else { draft = nil; return }
        checkpoint(snapshot); snapshot.marks[i] = mark; draft = nil
    }
    func changeColor(_ value: AnnotationColor) {
        guard !saving else { return }; color = value
        if var mark = selectedMark { mark.color = value; replace(mark) }
    }
    func changeArrowhead(_ value: AnnotationArrowhead) {
        guard !saving else { return }; arrowhead = value
        if var mark = selectedMark { mark.arrowhead = value; replace(mark) }
    }
    func beginStyleEdit() { guard !saving else { return }; styleBase = snapshot }
    func changeWidth(_ value: CGFloat) {
        guard !saving else { return }; width = value
        if let i = snapshot.marks.firstIndex(where: { $0.id == selectedID }), snapshot.marks[i].width != value {
            if styleBase == nil { checkpoint(snapshot) }
            snapshot.marks[i].width = value
        }
    }
    func endStyleEdit() {
        if let previous = styleBase, previous != snapshot { checkpoint(previous) }; styleBase = nil
    }
    func deleteSelection() {
        guard !saving, let id = selectedID, snapshot.marks.contains(where: { $0.id == id }) else { return }
        checkpoint(snapshot); snapshot.marks.removeAll { $0.id == id }; selectedID = nil; draft = nil
    }
    func removeCrop() { guard !saving, snapshot.crop != nil else { return }; checkpoint(snapshot); snapshot.crop = nil }
    func nudge(dx: CGFloat, dy: CGFloat) { if let mark = selectedMark { replace(mark.translated(by: CGSize(width: dx, height: dy), within: size)) } }
    func addText() {
        guard let point = textPoint, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if var mark = snapshot.marks.first(where: { $0.id == editingTextID }) { mark.text = String(text.prefix(400)); replace(mark) }
        else { commit(AnnotationMark(tool: .text, start: point, end: point, color: color, width: width, text: String(text.prefix(400)))) }
        textPoint = nil; text = ""; editingTextID = nil
    }
    func editSelectedText() {
        guard !saving, let mark = selectedMark, mark.tool == .text else { return }
        text = mark.text; textPoint = mark.start; editingTextID = mark.id
    }
    func undo() { guard !saving, let previous = undoStates.popLast() else { return }; redoStates.append(snapshot); snapshot = previous; draft = nil; synchronizeSelection() }
    func redo() { guard !saving, let next = redoStates.popLast() else { return }; undoStates.append(snapshot); snapshot = next; draft = nil; synchronizeSelection() }
    private func synchronizeSelection() {
        if let mark = selectedMark { color = mark.color; width = mark.width; arrowhead = mark.arrowhead } else { selectedID = nil }
    }
}

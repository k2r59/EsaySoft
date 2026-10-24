import AppKit
import SwiftUI

struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var model: AnnotationModel
    func makeNSView(context: Context) -> AnnotationScrollView { AnnotationScrollView(model: model) }
    func updateNSView(_ view: AnnotationScrollView, context: Context) {
        view.relayout(); view.canvas.needsDisplay = true
        view.window?.invalidateCursorRects(for: view.canvas)
    }
}
@MainActor final class AnnotationScrollView: NSScrollView {
    let canvas: AnnotationCanvasView
    private var previousZoom: CGFloat?
    init(model: AnnotationModel) {
        canvas = AnnotationCanvasView(model: model)
        super.init(frame: .zero)
        documentView = canvas; drawsBackground = true; backgroundColor = NSColor(StudioChrome.workspace)
        hasHorizontalScroller = true; hasVerticalScroller = true; autohidesScrollers = true
        scrollerStyle = .overlay; borderType = .noBorder
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); relayout() }
    func relayout() {
        let available = contentSize, scale = window?.backingScaleFactor ?? 1
        let zoom = canvas.model.zoom
        let size = zoom.map { CGSize(width: max(available.width, canvas.model.outputSize.width/scale*$0+40), height: max(available.height, canvas.model.outputSize.height/scale*$0+40)) } ?? available
        guard size.width > 0, size.height > 0, canvas.frame.size != size || previousZoom != zoom else { return }
        let oldFrame = canvas.frame, oldVisible = documentVisibleRect
        let center = CGPoint(x: oldFrame.width > 0 ? oldVisible.midX/oldFrame.width : 0.5, y: oldFrame.height > 0 ? oldVisible.midY/oldFrame.height : 0.5)
        canvas.frame.size = size; previousZoom = zoom
        let origin = CGPoint(x: max(0, min(size.width-available.width, size.width*center.x-available.width/2)), y: max(0, min(size.height-available.height, size.height*center.y-available.height/2)))
        contentView.scroll(to: origin); reflectScrolledClipView(contentView); canvas.needsDisplay = true
    }
}
@MainActor final class AnnotationCanvasView: NSView {
    let model: AnnotationModel
    private var anchor: CGPoint?
    private var originalMark: AnnotationMark?
    private var endpoint: Bool?
    init(model: AnnotationModel) { self.model = model; super.init(frame: .zero); wantsLayer = true; setAccessibilityLabel("Image à annoter") }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    private var frameStyle: AnnotationBackdrop { model.tool == .crop && !model.showingBackdrop ? AnnotationBackdrop() : model.snapshot.backdrop }
    private var sourceCrop: CGRect { model.tool == .crop && !model.showingBackdrop ? CGRect(origin:.zero,size:model.size) : model.effectiveCrop ?? CGRect(origin:.zero,size:model.size) }
    private var frameLayout: AnnotationBackdrop.Layout { frameStyle.layout(for:sourceCrop.size) }
    private var outputRect: CGRect {
        let scale = window?.backingScaleFactor ?? 1, pixels = frameLayout.size
        let size = model.zoom.map { CGSize(width:pixels.width/scale*$0,height:pixels.height/scale*$0) } ?? AnnotationRaster.fittedSize(pixels:pixels,available:CGSize(width:max(1,bounds.width-(frameStyle.enabled ? 112:56)),height:max(1,bounds.height-(frameStyle.enabled ? 112:56))),displayScale:scale)
        return CGRect(x:((bounds.width-size.width)/2*scale).rounded()/scale,y:((bounds.height-size.height)/2*scale).rounded()/scale,width:size.width,height:size.height)
    }
    var drawableRect: CGRect {
        let r = frameLayout.image, factor = outputRect.width/frameLayout.size.width
        return CGRect(x:outputRect.minX+r.minX*factor,y:outputRect.minY+r.minY*factor,width:r.width*factor,height:r.height*factor)
    }
    var imageRect: CGRect {
        let factor = drawableRect.width/sourceCrop.width
        return CGRect(x:drawableRect.minX-sourceCrop.minX*factor,y:drawableRect.minY-(model.size.height-sourceCrop.maxY)*factor,width:model.size.width*factor,height:model.size.height*factor)
    }
    func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), rect = imageRect
        return CGPoint(x: min(model.size.width, max(0, (p.x-rect.minX)/rect.width*model.size.width)), y: min(model.size.height, max(0, (rect.maxY-p.y)/rect.height*model.size.height)))
    }
    override func resetCursorRects() { addCursorRect(drawableRect, cursor: model.tool == .selection ? .arrow : model.tool == .text ? .iBeam : .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect, ratio = rect.width/model.size.width
        cg.setFillColor(NSColor(StudioChrome.workspace).cgColor); cg.fill(bounds)
        let raster = model.nativeImage ?? model.image
        let physicalScale = ratio*(window?.backingScaleFactor ?? 1)
        cg.interpolationQuality = physicalScale >= 1 && raster.width == Int(model.size.width) ? .none : .high
        cg.saveGState()
        let factor = outputRect.width/frameLayout.size.width
        cg.translateBy(x:outputRect.minX,y:outputRect.minY); cg.scaleBy(x:factor,y:factor)
        if frameStyle.enabled { BackdropRenderer.background(frameStyle,in:cg,layout:frameLayout,custom:model.customBackground) }
        BackdropRenderer.card(frameStyle,in:cg,layout:frameLayout) { content in
            cg.saveGState(); cg.clip(to:content)
            cg.translateBy(x:content.minX-sourceCrop.minX,y:content.minY-(model.size.height-sourceCrop.maxY))
            cg.draw(raster,in:CGRect(origin:.zero,size:model.size))
            AnnotationRenderer.draw(model.renderedMarks,in:cg,size:model.size)
            cg.restoreGState()
        }
        cg.restoreGState()
        cg.saveGState(); cg.translateBy(x:rect.minX,y:rect.minY); cg.scaleBy(x:ratio,y:ratio)
        if model.tool == .crop && !model.showingBackdrop, let crop = model.draft?.tool == .crop ? model.draft?.rect : model.snapshot.crop {
            let region = CGRect(x: crop.minX, y: model.size.height-crop.maxY, width: crop.width, height: crop.height)
            cg.saveGState(); cg.addRect(CGRect(origin: .zero, size: model.size)); cg.addRect(region); cg.clip(using: .evenOdd)
            cg.setFillColor(CGColor(gray: 0, alpha: 0.6)); cg.fill(CGRect(origin: .zero, size: model.size)); cg.restoreGState()
            cg.saveGState(); cg.setStrokeColor(AnnotationColor.mint.cgColor); cg.setLineWidth(1.5/ratio); cg.setLineDash(phase: 0, lengths: [6/ratio, 4/ratio]); cg.stroke(region); cg.restoreGState()
        }
        if let mark = model.renderedMarks.first(where: { $0.id == model.selectedID }) {
            let box = mark.bounds
            let selection = CGRect(x: box.minX, y: model.size.height-box.maxY, width: box.width, height: box.height).insetBy(dx: -3/ratio, dy: -3/ratio)
            cg.setStrokeColor(AnnotationColor.mint.cgColor); cg.setLineWidth(1/ratio)
            if mark.tool != .arrow { cg.setLineDash(phase: 0, lengths: [4/ratio, 3/ratio]); cg.stroke(selection); cg.setLineDash(phase: 0, lengths: []) }
            let handles = [AnnotationTool.arrow, .line, .rectangle, .ellipse, .filledRectangle, .spotlight, .highlight, .redact].contains(mark.tool) ? [mark.start, mark.end] : []
            for p in handles {
                let handle = CGRect(x: p.x-3.5/ratio, y: model.size.height-p.y-3.5/ratio, width: 7/ratio, height: 7/ratio)
                cg.setFillColor(CGColor(gray: 1, alpha: 1)); cg.fill(handle); cg.stroke(handle)
            }
        }
        cg.restoreGState()
    }
    override func mouseDown(with event: NSEvent) {
        guard !model.saving, !model.loadingNative, drawableRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        defer { needsDisplay = true }
        window?.makeFirstResponder(self)
        if model.textPoint != nil { model.addText() }
        let point = imagePoint(event); anchor = nil; originalMark = nil; endpoint = nil
        model.showingBackdrop = false
        if model.tool == .text { model.textPoint = point; return }
        if model.tool == .counter {
            let number = model.snapshot.marks.filter { $0.tool == .counter }.count+1
            model.commit(AnnotationMark(tool:.counter,start:point,end:point,color:model.color,width:model.width,text:String(number))); return
        }
        if model.tool == .selection {
            let tolerance = 9*model.size.width/imageRect.width
            if let selected = model.selectedMark, [.arrow, .line, .rectangle, .ellipse, .filledRectangle, .spotlight, .highlight, .redact].contains(selected.tool) {
                if hypot(point.x-selected.start.x, point.y-selected.start.y) < tolerance { endpoint = false; originalMark = selected }
                else if hypot(point.x-selected.end.x, point.y-selected.end.y) < tolerance { endpoint = true; originalMark = selected }
            }
            if originalMark == nil { originalMark = model.snapshot.marks.reversed().first { $0.contains(point, tolerance: tolerance) } }
            model.select(originalMark?.id)
            if event.clickCount == 2, originalMark?.tool == .text { model.editSelectedText(); return }
            if let mark = originalMark { anchor = point; model.draft = mark }
            return
        }
        anchor = point; model.selectedID = nil
        model.draft = AnnotationMark(tool: model.tool, start: point, end: point, color: model.color, width: model.width, points: model.tool == .pencil ? [point] : [], arrowhead: model.arrowhead)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor, !model.saving else { return }
        defer { needsDisplay = true }
        let point = imagePoint(event)
        if var mark = originalMark {
            if let endpoint { if endpoint { mark.end = point } else { mark.start = point }; model.draft = mark }
            else { model.draft = mark.translated(by: CGSize(width: point.x-anchor.x, height: point.y-anchor.y), within: model.size) }
        } else {
            model.draft?.end = point
            if model.draft?.tool == .pencil, let last = model.draft?.points.last, hypot(last.x-point.x, last.y-point.y) >= max(1, model.width/4), (model.draft?.points.count ?? 0) < 10_000 { model.draft?.points.append(point) }
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard anchor != nil else { return }; mouseDragged(with: event)
        defer { anchor = nil; originalMark = nil; endpoint = nil; needsDisplay = true }
        guard let mark = model.draft else { return }
        if originalMark != nil {
            if endpoint != nil {
                let valid = (mark.tool == .arrow || mark.tool == .line) ? hypot(mark.end.x-mark.start.x, mark.end.y-mark.start.y) > 3 : mark.rect.width >= 2 && mark.rect.height >= 2
                if !valid { model.draft = nil; return }
            }
            model.replace(mark); return
        }
        let distance = hypot(mark.end.x-mark.start.x, mark.end.y-mark.start.y)
        if (mark.tool == .pencil && mark.points.count > 1) || (distance > 3 && (mark.tool == .arrow || mark.tool == .line || (mark.rect.width >= 2 && mark.rect.height >= 2))) { model.commit(mark) }
        else { model.draft = nil }
    }
    override func keyDown(with event: NSEvent) {
        guard !model.saving else { return }
        defer { needsDisplay = true }
        let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117: model.deleteSelection()
        case 123: model.nudge(dx: -delta, dy: 0)
        case 124: model.nudge(dx: delta, dy: 0)
        case 125: model.nudge(dx: 0, dy: delta)
        case 126: model.nudge(dx: 0, dy: -delta)
        case 53:
            if model.draft != nil { model.draft = nil; anchor = nil; originalMark = nil }
            else { model.select(nil) }
        default: super.keyDown(with: event)
        }
    }
}

import AppKit
import SwiftUI
import CoreImage
import UniformTypeIdentifiers

enum DrawTool: String, CaseIterable { case arrow="Flèche", rectangle="Cadre", ellipse="Ellipse", pen="Crayon", highlight="Surligner", redact="Masquer", text="Texte", counter="Numéro" }
struct Mark { var tool: DrawTool; var points: [NSPoint]; var color: NSColor; var text: String = ""; var width: CGFloat = 4 }
final class EditorController: NSWindowController, NSWindowDelegate {
    let canvas: AnnotationView
    unowned let coordinator: AppDelegate
    init(image: NSImage, owner: AppDelegate) {
        self.coordinator=owner; canvas=AnnotationView(image:image)
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:1340,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init(window:w); w.title="EasyShoot · Éditeur"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent=true;w.backgroundColor=NSColor(Color.esBackground);w.center(); w.minSize=NSSize(width:1060,height:720)
        w.contentView=NSHostingView(rootView:EditorShell(controller:self).preferredColorScheme(.dark))
        w.delegate=self
    }
    required init?(coder:NSCoder) { fatalError() }
    func windowWillClose(_ notification:Notification) {
        canvas.changed=nil
        window?.contentView=nil
        coordinator.editors.removeAll { $0 === self }
    }
    @objc func changeTool(_ sender:NSSegmentedControl) { canvas.tool=DrawTool.allCases[sender.selectedSegment] }
    @objc func changeColor(_ sender:NSColorWell) { canvas.color=sender.color }
    @objc func undoMark() { if !canvas.marks.isEmpty { canvas.marks.removeLast();canvas.needsDisplay=true } }
    @objc func clearMarks() { canvas.marks=[];canvas.needsDisplay=true }
    @objc func extract() { coordinator.recognize(canvas.rendered()) }
    @objc func copyImage() { NSPasteboard.general.clearContents();if NSPasteboard.general.writeObjects([canvas.rendered()]) {coordinator.sounds.play(.copy)} }
    @objc func exportImage() {
        let p=NSSavePanel();p.allowedContentTypes=[.png];p.nameFieldStringValue="EasyShoot.png"
        guard p.runModal() == .OK,let u=p.url,let tiff=canvas.rendered().tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.png,properties:[:]) else{return}
        do { try data.write(to:u) } catch { coordinator.fail(error) }
    }
    @objc func pin() {
        let image=canvas.rendered();let size=NSSize(width:420,height:420*image.size.height/image.size.width)
        let panel=NSPanel(contentRect:NSRect(origin:NSPoint(x:100,y:100),size:size),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
        panel.title="EasyShoot · Épinglé";panel.level = .floating;panel.isFloatingPanel=true;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
        let v=NSImageView();v.image=image;v.imageScaling = .scaleProportionallyUpOrDown;panel.contentView=v;panel.delegate=coordinator;coordinator.windows.append(panel);panel.makeKeyAndOrderFront(nil)
    }
}
final class AnnotationView:NSView {
    let image:NSImage
    var tool:DrawTool = .arrow;var color:NSColor = .systemOrange
    var marks:[Mark]=[];var draft:Mark?;var strokeWidth:CGFloat=4;var changed:(()->Void)?
    init(image:NSImage) { self.image=image;super.init(frame:NSRect(origin:.zero,size:image.size)) }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) { image.draw(in:bounds);for m in marks { paint(m) };if let m=draft { paint(m) } }
    func paint(_ m:Mark) {
        guard let a=m.points.first,let b=m.points.last else{return}
        let r=NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
        let width=m.width
        m.color.setStroke();m.color.setFill()
        let p=NSBezierPath();p.lineWidth=width;p.lineCapStyle = .round;p.lineJoinStyle = .round
        switch m.tool {
        case .rectangle: p.appendRect(r);p.stroke()
        case .ellipse: p.appendOval(in:r);p.stroke()
        case .redact: NSColor.black.setFill();r.fill()
        case .highlight: m.color.withAlphaComponent(0.32).setFill();r.fill()
        case .pen: p.move(to:a);for q in m.points.dropFirst() { p.line(to:q) };p.stroke()
        case .arrow:
            p.move(to:a);p.line(to:b);let angle=atan2(b.y-a.y,b.x-a.x);let length=width*5
            p.move(to:NSPoint(x:b.x-length*cos(angle-0.45),y:b.y-length*sin(angle-0.45)));p.line(to:b);p.line(to:NSPoint(x:b.x-length*cos(angle+0.45),y:b.y-length*sin(angle+0.45)));p.stroke()
        case .text: (m.text as NSString).draw(at:a,withAttributes:[.font:NSFont.systemFont(ofSize:max(22,image.size.width/32),weight:.bold),.foregroundColor:m.color,.strokeColor:NSColor.black,.strokeWidth: -1])
        case .counter:
            let size=max(36,image.size.width/24);let circle=NSRect(x:a.x-size/2,y:a.y-size/2,width:size,height:size);NSBezierPath(ovalIn:circle).fill()
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size*0.58,weight:.bold),.foregroundColor:NSColor.white];let s=m.text as NSString;let sz=s.size(withAttributes:attrs);s.draw(at:NSPoint(x:a.x-sz.width/2,y:a.y-sz.height/2),withAttributes:attrs)
        }
    }
    override func mouseDown(with event:NSEvent) {
        let a=convert(event.locationInWindow,from:nil)
        if tool == .text { let alert=NSAlert();alert.messageText="Ajouter du texte";let field=NSTextField(frame:NSRect(x:0,y:0,width:320,height:28));alert.accessoryView=field;alert.addButton(withTitle:"Ajouter");alert.addButton(withTitle:"Annuler");alert.window.initialFirstResponder=field;if alert.runModal() == .alertFirstButtonReturn && !field.stringValue.isEmpty { marks.append(Mark(tool:.text,points:[a],color:color,text:field.stringValue));needsDisplay=true;changed?() };return }
        if tool == .counter { marks.append(Mark(tool:.counter,points:[a],color:color,text:String(marks.filter{$0.tool == .counter}.count+1)));needsDisplay=true;changed?();return }
        draft=Mark(tool:tool,points:[a,a],color:color,width:strokeWidth)
    }
    override func mouseDragged(with event:NSEvent) { guard draft != nil else{return};let q=convert(event.locationInWindow,from:nil);if tool == .pen { draft?.points.append(q) } else { draft?.points[1]=q };needsDisplay=true }
    override func mouseUp(with event:NSEvent) { if let m=draft { marks.append(m) };draft=nil;needsDisplay=true;changed?() }
    func rendered() -> NSImage {
        let width=Int(image.size.width),height=Int(image.size.height)
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else { return image }
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        image.draw(in:NSRect(origin:.zero,size:image.size));for m in marks { paint(m) }
        NSGraphicsContext.restoreGraphicsState()
        let result=NSImage(size:image.size);result.addRepresentation(bitmap);return result
    }
}

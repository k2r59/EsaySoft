import SwiftUI
import AppKit
import ImageIO

final class ScrollingSession:ObservableObject {
    @Published var count=0
    @Published var height=0
    @Published var preview:NSImage?
    @Published var status="Défile lentement, puis marque une pause."
    @Published var warning=false
    @Published var busy=false
    @Published var finishing=false
    @Published var paused=false
    var snapshotProvider:(() async throws->CGImage)?
    var completed:((URL)->Void)?
    var outputDirectory:URL?
    let rect:CGRect
    unowned let owner:AppDelegate
    weak var panel:NSWindow?
    private var accumulator=ScrollAccumulator()
    private var candidate:CGImage?
    private var loop:Task<Void,Never>?
    private var stopped=false
    init(rect:CGRect,owner:AppDelegate) {self.rect=rect;self.owner=owner}
    func begin() {
        loop=Task { @MainActor [weak self] in
            guard let self else{return}
            while !Task.isCancelled && !stopped {
                if !paused {await sample()}
                try? await Task.sleep(for:.milliseconds(800))
            }
        }
    }
    @MainActor func snapshot() async throws->CGImage {
        if let snapshotProvider {return try await snapshotProvider()}
        // The floating controls can overlap a large viewport. Hide only during the grab.
        let primaryTop=NSScreen.screens.first?.frame.maxY ?? 0
        let controlsRect=panel.map{CGRect(x:$0.frame.minX,y:primaryTop-$0.frame.maxY,width:$0.frame.width,height:$0.frame.height)}
        let overlaps=controlsRect?.intersects(rect) ?? false
        if overlaps {panel?.orderOut(nil)}
        try await Task.sleep(for:.milliseconds(100))
        defer {if overlaps && !stopped {panel?.orderFrontRegardless()}}
        return try await NativeScreenCapture.region(rect)
    }

    @MainActor func sample(force:Bool=false) async {
        guard !busy,!stopped else{return};busy=true
        defer {busy=false}
        do {
            let image=try await snapshot()
            guard !stopped else{return}
            if !force,accumulator.last != nil {
                defer {candidate=image}
                guard let candidate else{return}
                let stable=try await Task.detached {try ScrollStitcher.match(candidate,image)}.value
                guard stable.kind == .duplicate else {status="Défilement détecté… attends une seconde.";return}
            }
            var buffer=accumulator
            let (updated,match)=try await Task.detached { ()->(ScrollAccumulator,ScrollMatch) in let m=try buffer.append(image);return(buffer,m) }.value
            guard !stopped else{return}
            accumulator=updated
            switch match.kind {
            case .shifted:
                count=accumulator.strips.count;height=accumulator.height;preview=NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height));warning=false;status=count == 1 ? "Première image capturée. Défile vers le bas.":"Portion ajoutée · continue vers le bas."
            case .duplicate:if warning {warning=false;status="Zone déjà assemblée. Tu peux continuer ou terminer."}
            case .unmatched:warning=true;status="Raccord introuvable. Remonte un peu, puis défile moins loin."
            }
        } catch {warning=true;status=error.localizedDescription;paused=true}
    }
    @MainActor func finish() async {
        guard !busy,!finishing,!stopped else{return};finishing=true;paused=true
        // Preserve the last stable portion when the user ends between polling cycles.
        await sample(force:true)
        guard count>0,!warning else{finishing=false;return}
        do {
            let parts=accumulator.strips
            let url=(outputDirectory ?? owner.store).appendingPathComponent("Capture-defilante-\(UUID().uuidString).png")
            try await Task.detached {try ScrollStitcher.writePNG(ScrollStitcher.assemble(parts),to:url)}.value
            stopped=true;loop?.cancel();panel?.orderOut(nil);accumulator=ScrollAccumulator();candidate=nil;preview=nil;if let completed {completed(url)} else {owner.showQuickCapture(url)}
        } catch {warning=true;status=error.localizedDescription;finishing=false;paused=true}
    }
    func cancel() {stopped=true;loop?.cancel();panel?.orderOut(nil);accumulator=ScrollAccumulator();candidate=nil;preview=nil}
    deinit {loop?.cancel()}
}

final class ScrollingController:NSWindowController,NSWindowDelegate {
    let session:ScrollingSession
    init(rect:CGRect,owner:AppDelegate) {
        session=ScrollingSession(rect:rect,owner:owner)
        let visible=(NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let primaryTop=NSScreen.screens.first?.frame.maxY ?? 0
        let selected=CGRect(x:rect.minX,y:primaryTop-rect.maxY,width:rect.width,height:rect.height)
        let positions=[NSPoint(x:visible.maxX-350,y:visible.minY+24),NSPoint(x:visible.minX+24,y:visible.minY+24),NSPoint(x:visible.maxX-350,y:visible.maxY-470),NSPoint(x:visible.minX+24,y:visible.maxY-470)]
        let position=positions.first{!NSRect(origin:$0,size:NSSize(width:325,height:442)).intersects(selected.insetBy(dx:-10,dy:-10))} ?? positions[0]
        let panel=NSPanel(contentRect:NSRect(origin:position,size:NSSize(width:325,height:442)),styleMask:[.titled,.closable,.utilityWindow,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init(window:panel);panel.title="Capture défilante";panel.level = .floating;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.backgroundColor=NSColor(Color.esBackground);panel.delegate=self
        session.panel=panel;panel.contentView=NSHostingView(rootView:ScrollingCaptureView(session:session).preferredColorScheme(.dark))
    }
    required init?(coder:NSCoder) {fatalError()}
    func windowShouldClose(_ sender:NSWindow)->Bool { !session.finishing }
    func windowWillClose(_ notification:Notification) {session.cancel()}
}
struct ScrollingCaptureView:View {
    @ObservedObject var session:ScrollingSession
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Image(systemName:"rectangle.expand.vertical").foregroundStyle(Color.esAccent);Text("Capture défilante").font(.system(size:15,weight:.semibold));Spacer();Circle().fill(session.paused ? .orange:.green).frame(width:6,height:6)}
            Text("Défile dans la zone sélectionnée. Marque une pause entre chaque portion.").font(.system(size:11)).foregroundStyle(Color.esMuted).lineSpacing(4)
            ZStack {
                RoundedRectangle(cornerRadius:12).fill(.black.opacity(0.2))
                if let image=session.preview {Image(nsImage:image).resizable().scaledToFit().padding(9)} else {ProgressView().tint(.esAccent)}
                VStack {Spacer();HStack {Spacer();Text("\(session.count) portion\(session.count>1 ? "s":"")").font(.system(size:10,weight:.medium)).padding(7).background(.black.opacity(0.7),in:Capsule())}.padding(10)}
            }.frame(height:155)
            HStack {Label("Assemblage vertical",systemImage:"arrow.down");Spacer();Text("\(session.height) px").monospacedDigit()}.font(.system(size:10)).foregroundStyle(Color.esMuted)
            Text(session.status).font(.system(size:11)).foregroundStyle(session.warning ? Color.esAccent:Color.esMuted).frame(height:34,alignment:.topLeading)
            HStack {ActionButton(title:session.paused ? "Reprendre":"Pause",symbol:session.paused ? "play":"pause") {session.paused.toggle()}.disabled(session.finishing);Spacer();ActionButton(title:session.finishing ? "Assemblage…":"Terminer",symbol:"checkmark",primary:true) {Task {await session.finish()}}.disabled(session.busy || session.count == 0 || session.finishing)}
        }.padding(20).background(Color.esBackground)
    }
}

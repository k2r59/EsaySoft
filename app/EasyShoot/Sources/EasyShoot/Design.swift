import SwiftUI
import AppKit

extension Color {
    static let esBackground = Color(red:0.055,green:0.065,blue:0.085)
    static let esSidebar = Color(red:0.075,green:0.085,blue:0.105)
    static let esSurface = Color(red:0.105,green:0.12,blue:0.145)
    static let esMuted = Color(red:0.55,green:0.59,blue:0.65)
    static let esAccent = Color(red:1,green:0.47,blue:0.28)
}
struct Surface: ViewModifier {
    func body(content:Content) -> some View { content.padding(20).background(Color.esSurface,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(.white.opacity(0.06),lineWidth:1)) }
}
struct Brand:View {
    var body:some View { HStack(spacing:10) { Image(systemName:"viewfinder").font(.system(size:19,weight:.semibold)).foregroundStyle(Color.esAccent).frame(width:36,height:36).background(Color.esAccent.opacity(0.12),in:RoundedRectangle(cornerRadius:11));Text("EasyShoot").font(.system(size:19,weight:.bold,design:.rounded)).tracking(-0.5) } }
}
struct KeyCap:View { let label:String;var body:some View { Text(label).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(Color.esMuted).padding(.horizontal,7).padding(.vertical,4).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:5)).overlay(RoundedRectangle(cornerRadius:5).stroke(.white.opacity(0.08))) } }
struct ActionButton:View { let title:String;let symbol:String;var primary=false;let action:()->Void;var body:some View { Button(action:action) { Label(title,systemImage:symbol).font(.system(size:12,weight:.semibold)).padding(.horizontal,15).frame(height:36).foregroundStyle(primary ? Color.black.opacity(0.88):Color.white).background(primary ? Color.esAccent:Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:9)) }.buttonStyle(HoverButtonStyle()) } }

final class HomeController:NSWindowController {
    init(owner:AppDelegate) {
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init(window:w);w.title="EasyShoot";w.titleVisibility = .hidden;w.titlebarAppearsTransparent=true;w.backgroundColor=NSColor(Color.esBackground);w.minSize=NSSize(width:1040,height:730);w.center();w.isReleasedWhenClosed=false
        w.contentView=NSHostingView(rootView:HomeView(owner:owner).preferredColorScheme(.dark))
    }
    required init?(coder:NSCoder) { fatalError() }
}
struct HomeView:View {
    unowned let owner:AppDelegate
    @State private var page=0
    @StateObject private var library=CaptureLibrary()
    private var captures:[CaptureEntry] { library.entries }
    @State private var authorized=CGPreflightScreenCaptureAccess()
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                Brand().padding(.top,57).padding(.bottom,38)
                Text("ESPACE DE TRAVAIL").font(.system(size:9,weight:.bold)).tracking(1.6).foregroundStyle(Color.esMuted).padding(.bottom,14)
                nav("Capturer", "viewfinder", 0)
                nav("Bibliothèque", "square.grid.2x2", 1)
                nav("Préférences", "slider.horizontal.3", 2)
                Spacer()
                VStack(alignment:.leading,spacing:9) { HStack(spacing:7) { Circle().fill(Color.green.opacity(0.85)).frame(width:5,height:5);Text("100 % sur ton Mac").font(.system(size:11,weight:.medium)) };Text("Tes captures restent privées.\nAucun compte nécessaire.").font(.system(size:11)).foregroundStyle(Color.esMuted).lineSpacing(4) }.padding(15).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                HStack { Text("EasyShoot").font(.system(size:10,weight:.medium));Spacer();Text("0.2 · Aperçu").font(.system(size:10)).foregroundStyle(Color.esMuted) }.padding(.top,22)
            }.padding(.horizontal,22).padding(.bottom,24).frame(width:220).background(Color.esSidebar)
            Rectangle().fill(.white.opacity(0.055)).frame(width:1)
            ScrollView {
                VStack(alignment:.leading,spacing:28) {
                    HStack { Text(page == 0 ? "CAPTURE" : page == 1 ? "BIBLIOTHÈQUE" : "PRÉFÉRENCES").font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(Color.esMuted);Spacer();Button { if authorized {owner.settings()} else {owner.openScreenPermissions()} } label: { Label(authorized ? "Capture autorisée" : "Autoriser la capture",systemImage:authorized ? "checkmark.shield" : "lock.shield").font(.system(size:11,weight:.medium)).foregroundStyle(authorized ? Color.esMuted : Color.esAccent) }.buttonStyle(HoverButtonStyle()) }
                    if page == 0 { capturePage }
                    else if page == 1 { libraryPage }
                    else { settingsPage }
                }.padding(.horizontal,40).padding(.top,52).padding(.bottom,32)
            }.background(Color.esBackground)
        }.onAppear(perform:refresh).onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in refresh() }.onReceive(NotificationCenter.default.publisher(for:Notification.Name("EasyShootCapturesChanged"))) { _ in refresh() }
    }
    func nav(_ title:String,_ symbol:String,_ id:Int)->some View { Button { page=id;refresh() } label: { HStack(spacing:12) { Image(systemName:symbol).font(.system(size:15)).frame(width:19);Text(title).font(.system(size:13,weight:page == id ? .semibold:.regular));Spacer();if page == id { RoundedRectangle(cornerRadius:2).fill(Color.esAccent).frame(width:3,height:15) } }.foregroundStyle(page == id ? Color.white:Color.esMuted).padding(.horizontal,13).frame(height:43).background(page == id ? Color.white.opacity(0.07):Color.clear,in:RoundedRectangle(cornerRadius:9)) }.buttonStyle(HoverButtonStyle()).padding(.bottom,5) }
    var capturePage:some View {
        VStack(alignment:.leading,spacing:27) {
            VStack(alignment:.leading,spacing:10) { Text("Une idée. Une capture.").font(.system(size:34,weight:.semibold)).tracking(-1.2);Text("Capture l’essentiel, ajoute ton regard et passe à la suite.").font(.system(size:13)).foregroundStyle(Color.esMuted) }
            HStack(spacing:26) {
                VStack(alignment:.leading,spacing:13) {
                    Text("JUSTE CE QU’IL FAUT.").font(.system(size:9,weight:.bold)).tracking(1.8).foregroundStyle(Color.esAccent)
                    Text("Ton prochain visuel\ncommence ici.").font(.system(size:27,weight:.semibold)).tracking(-0.7).lineSpacing(2)
                    Text("Sélectionne une zone. On s’occupe du reste.").font(.system(size:12)).foregroundStyle(Color.esMuted)
                    HStack(spacing:10) { ActionButton(title:"Capturer une zone",symbol:"plus",primary:true) { capture(owner.area) };KeyCap(label:"⌃ ⌥ ⌘ 2") }.padding(.top,8)
                }
                Spacer(minLength:0)
                ZStack {
                    RoundedRectangle(cornerRadius:16).fill(Color.esAccent.opacity(0.06)).frame(width:185,height:158).rotationEffect(.degrees(-9))
                    RoundedRectangle(cornerRadius:12).fill(Color(red:0.16,green:0.18,blue:0.22)).frame(width:178,height:132).overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.09)))
                    VStack(alignment:.leading,spacing:11) { HStack(spacing:4) { ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.2)).frame(width:4,height:4) } };RoundedRectangle(cornerRadius:3).fill(.white.opacity(0.7)).frame(width:68,height:7);RoundedRectangle(cornerRadius:3).fill(.white.opacity(0.13)).frame(width:112,height:5);RoundedRectangle(cornerRadius:3).fill(.white.opacity(0.13)).frame(width:90,height:5) }.offset(x:-7,y:-2)
                    Image(systemName:"viewfinder").font(.system(size:100,weight:.ultraLight)).foregroundStyle(Color.esAccent).offset(x:8,y:8)
                    Image(systemName:"cursorarrow").font(.system(size:25,weight:.semibold)).foregroundStyle(.white).shadow(radius:4).offset(x:65,y:52)
                }.frame(width:205,height:180)
            }.padding(27).frame(maxWidth:.infinity,alignment:.leading).background(LinearGradient(colors:[Color.esSurface,Color(red:0.12,green:0.105,blue:0.12)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.07)))
            HStack(spacing:12) { captureCard("Fenêtre","Une app, sans distraction.","macwindow") { capture(owner.window) };captureCard("Écran entier","Tout garder en un instant.","display") { capture(owner.fullscreen) };captureCard("Extraire le texte","Sélection à la souris · ⌃⌥⌘T","text.viewfinder") { capture(owner.ocr) } }
            HStack(spacing:12) { captureCard("Capture défilante","Une page entière, en une image.","rectangle.expand.vertical") { capture(owner.scrollingCapture) };captureCard("Montage vidéo","Couper, recadrer et exporter.","film.stack") { owner.openVideo() } }
            HStack { Text("Captures récentes").font(.system(size:15,weight:.semibold));Spacer();Button("Tout voir →") { page=1;refresh() }.buttonStyle(HoverButtonStyle()).font(.system(size:11,weight:.medium)).foregroundStyle(Color.esMuted) }
            recentGrid(limit:3)
            HStack(spacing:18) { Button { owner.openImage() } label: { Label("Ouvrir une image",systemImage:"folder") };Button { owner.pasteImage() } label: { Label("Coller une image",systemImage:"clipboard") };Spacer();Button { owner.record() } label: { Label(owner.recorder.isRecording ? "Arrêter la vidéo" : "Enregistrer l’écran",systemImage:"record.circle") } }.buttonStyle(HoverButtonStyle()).font(.system(size:11)).foregroundStyle(Color.esMuted)
        }
    }
    func captureCard(_ title:String,_ detail:String,_ symbol:String,_ action:@escaping ()->Void)->some View { Button(action:action) { VStack(alignment:.leading,spacing:16) { Image(systemName:symbol).font(.system(size:21,weight:.light)).foregroundStyle(Color.esAccent);VStack(alignment:.leading,spacing:6) { Text(title).font(.system(size:13,weight:.semibold)).foregroundStyle(.white);Text(detail).font(.system(size:10)).foregroundStyle(Color.esMuted) } }.frame(maxWidth:.infinity,alignment:.leading).modifier(Surface()) }.buttonStyle(HoverButtonStyle()) }
    var libraryPage:some View { VStack(alignment:.leading,spacing:24) { HStack { VStack(alignment:.leading,spacing:9) { Text("Ta bibliothèque.").font(.system(size:34,weight:.semibold)).tracking(-1);Text("\(captures.count) capture\(captures.count == 1 ? "":"s") · conservées sur ce Mac").foregroundStyle(Color.esMuted).font(.system(size:13)) };Spacer();ActionButton(title:"Ouvrir le dossier",symbol:"folder") { NSWorkspace.shared.open(owner.store) } };recentGrid(limit:60) } }
    @ViewBuilder func recentGrid(limit:Int)->some View {
        if captures.isEmpty {
            VStack(spacing:12) { Image(systemName:"photo.on.rectangle.angled").font(.system(size:27,weight:.light)).foregroundStyle(Color.esMuted);Text("Ton espace attend sa première capture.").font(.system(size:12,weight:.medium));Text("Tes images apparaîtront ici, prêtes à être retrouvées.").font(.system(size:11)).foregroundStyle(Color.esMuted) }.frame(maxWidth:.infinity).frame(height:140).background(.white.opacity(0.02),in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).strokeBorder(.white.opacity(0.08),style:StrokeStyle(lineWidth:1,dash:[5])))
        } else {
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                ForEach(Array(captures.prefix(limit))) { entry in
                    Button {
                        if entry.isVideo { owner.showVideoEditor(entry.url) }
                        else if let image=NSImage(contentsOf:entry.url) { owner.showEditor(image) }
                    } label: {
                        VStack(alignment:.leading,spacing:0) {
                            CaptureThumbnail(entry:entry).frame(height:110).frame(maxWidth:.infinity).background(.black.opacity(0.2))
                            VStack(alignment:.leading,spacing:5) {
                                Text(entry.isVideo ? "Enregistrement":"Capture d’écran").font(.system(size:11,weight:.medium))
                                Text(entry.date.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(Color.esMuted)
                            }.padding(12)
                        }.background(Color.esSurface,in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.06)))
                    }.buttonStyle(HoverButtonStyle())
                }
            }
        }
    }
    var settingsPage:some View { VStack(alignment:.leading,spacing:24) { Text("À ta façon.").font(.system(size:34,weight:.semibold)).tracking(-1);Text("Les essentiels, sans complexité.").font(.system(size:13)).foregroundStyle(Color.esMuted)
        VStack(alignment:.leading,spacing:22) { HStack { Label("Raccourci de capture",systemImage:"keyboard");Spacer();KeyCap(label:"⌃ ⌥ ⌘ 2") };Divider().overlay(.white.opacity(0.05));HStack { Label("Extraire le texte à l’écran",systemImage:"text.viewfinder");Spacer();KeyCap(label:"⌃ ⌥ ⌘ T") };Divider().overlay(.white.opacity(0.05));HStack { Label("Enregistrement de l’écran",systemImage:"lock.shield");Spacer();ActionButton(title:"Gérer l’autorisation",symbol:"arrow.up.right") { owner.settings() } };Divider();HStack { Label("Stockage local",systemImage:"internaldrive");Spacer();ActionButton(title:"Afficher dans le Finder",symbol:"folder") { NSWorkspace.shared.open(owner.store) } };Divider();HStack { Label("MCP local · stdio",systemImage:"point.3.connected.trianglepath.dotted");Spacer();ActionButton(title:"Copier la configuration",symbol:"doc.on.doc") { owner.copyMCPConfiguration() } };Text(owner.store.path).font(.system(size:10,design:.monospaced)).foregroundStyle(Color.esMuted).textSelection(.enabled) }.font(.system(size:12)).modifier(Surface())
        VStack(alignment:.leading,spacing:12) { Text("Version de développement").font(.system(size:13,weight:.semibold));Text("Capture et annotation, OCR local, capture défilante verticale et montage vidéo. Les GIF et la caméra restent à développer.").font(.system(size:12)).foregroundStyle(Color.esMuted).lineSpacing(5) }.modifier(Surface())
    } }
    func capture(_ action:()->Void) { owner.home?.window?.orderOut(nil);action() }
    func refresh() { authorized=CGPreflightScreenCaptureAccess();library.refresh(in:owner.store) }
}

extension DrawTool {
    var symbol:String { switch self { case .arrow:return "arrow.up.right";case .rectangle:return "rectangle";case .ellipse:return "circle";case .pen:return "pencil.tip";case .highlight:return "highlighter";case .redact:return "square.fill";case .text:return "textformat";case .counter:return "1.circle" } }
    var hint:String { switch self { case .arrow:return "Glisse pour indiquer un détail.";case .rectangle:return "Encadre une zone à mettre en valeur.";case .ellipse:return "Entoure un élément important.";case .pen:return "Dessine librement sur ta capture.";case .highlight:return "Glisse sur une zone pour la surligner.";case .redact:return "Masque une information avec un aplat opaque.";case .text:return "Clique sur l’image pour ajouter du texte.";case .counter:return "Clique pour numéroter les étapes." } }
}
struct CanvasHost:NSViewRepresentable {
    let canvas:AnnotationView;let fit:CGFloat;let zoom:CGFloat
    func makeNSView(context:Context)->NSScrollView { let s=NSScrollView();let clip=CenteredClipView();clip.drawsBackground=false;s.contentView=clip;s.hasVerticalScroller=true;s.hasHorizontalScroller=true;s.drawsBackground=false;s.documentView=canvas;s.allowsMagnification=true;s.minMagnification=0.05;s.maxMagnification=5;s.magnification=fit;return s }
    func updateNSView(_ s:NSScrollView,context:Context) { s.magnification=zoom == 0 ? fit:zoom }
}
struct EditorShell:View {
    unowned let controller:EditorController
    @State private var tool:DrawTool = .arrow
    @State private var selectedColor=0
    @State private var stroke=4.0
    @State private var count=0
    @State private var zoom:CGFloat=0
    @State private var notice=""
    private let palette:[Color]=[.esAccent,Color(red:0.55,green:0.6,blue:1),Color(red:0.3,green:0.8,blue:0.6),Color(red:1,green:0.79,blue:0.3),.white,Color(red:0.12,green:0.14,blue:0.19)]
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:14) {
                Button { controller.window?.orderOut(nil);controller.coordinator.showHome() } label: { Image(systemName:"chevron.left").font(.system(size:13,weight:.semibold)).foregroundStyle(Color.esMuted).frame(width:30,height:32).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(HoverButtonStyle()).help("Retour à l’espace de travail")
                VStack(alignment:.leading,spacing:4) { Text("Capture d’écran").font(.system(size:14,weight:.semibold));Text("\(Int(controller.canvas.image.size.width)) × \(Int(controller.canvas.image.size.height)) px  ·  Modifications locales").font(.system(size:10)).foregroundStyle(Color.esMuted) }
                Spacer()
                Button { controller.undoMark();count=controller.canvas.marks.count } label: { Image(systemName:"arrow.uturn.backward").font(.system(size:14)).foregroundStyle(count == 0 ? Color.esMuted.opacity(0.4):Color.esMuted).frame(width:32,height:32) }.buttonStyle(HoverButtonStyle()).disabled(count == 0).keyboardShortcut("z",modifiers:.command).help("Annuler la dernière annotation · ⌘Z")
                Rectangle().fill(.white.opacity(0.08)).frame(width:1,height:24)
                ActionButton(title:"Épingler",symbol:"pin") { controller.pin();notify("Image épinglée") }
                ActionButton(title:"Copier",symbol:"square.on.square") { controller.copyImage();notify("Image copiée dans le presse-papiers") }.keyboardShortcut("c",modifiers:.command)
                ActionButton(title:"Exporter",symbol:"square.and.arrow.up",primary:true) { controller.exportImage() }.keyboardShortcut("s",modifiers:.command)
            }.padding(.horizontal,24).padding(.top,41).padding(.bottom,20)
            Rectangle().fill(.white.opacity(0.07)).frame(height:1)
            HStack(spacing:0) {
                VStack(spacing:0) {
                    HStack(spacing:5) {
                        ForEach(DrawTool.allCases,id:\.self) { t in Button { tool=t;controller.canvas.tool=t } label: { Image(systemName:t.symbol).font(.system(size:16,weight:.medium)).foregroundStyle(tool == t ? Color.esAccent:Color.esMuted).frame(width:43,height:37).background(tool == t ? Color.esAccent.opacity(0.12):Color.clear,in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(HoverButtonStyle()).help(t.rawValue) }
                        Spacer()
                        Text(tool.rawValue).font(.system(size:11,weight:.medium)).foregroundStyle(Color.esMuted)
                    }.padding(.horizontal,20).padding(.vertical,12).background(Color.esSidebar)
                    GeometryReader { geo in
                        let fit=min((geo.size.width-60)/controller.canvas.image.size.width,(geo.size.height-60)/controller.canvas.image.size.height)
                        ZStack {
                            Color(red:0.045,green:0.05,blue:0.065)
                            Canvas { context,size in
                                for x in stride(from:10.0,to:size.width,by:18) { for y in stride(from:10.0,to:size.height,by:18) { context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:1,height:1)),with:.color(.white.opacity(0.07))) } }
                            }
                            CanvasHost(canvas:controller.canvas,fit:max(0.05,fit),zoom:zoom).padding(30)
                        }
                    }
                    HStack(spacing:8) {
                        Image(systemName:"cursorarrow").font(.system(size:10));Text(tool.hint).font(.system(size:10));Spacer()
                        Button { zoom=max(0.1,(zoom == 0 ? 1:zoom)-0.25) } label: { Image(systemName:"minus") }.help("Réduire")
                        Button { zoom=0 } label: { Text(zoom == 0 ? "Ajuster":"\(Int(zoom*100)) %").font(.system(size:10,design:.monospaced)).frame(width:52) }.help("Ajuster à la fenêtre")
                        Button { zoom=min(4,(zoom == 0 ? 1:zoom)+0.25) } label: { Image(systemName:"plus") }.help("Agrandir")
                    }.buttonStyle(HoverButtonStyle()).foregroundStyle(Color.esMuted).padding(.horizontal,20).frame(height:40).background(Color.esSidebar)
                }
                Rectangle().fill(.white.opacity(0.07)).frame(width:1)
                VStack(alignment:.leading,spacing:25) {
                    HStack { Text("PROPRIÉTÉS").font(.system(size:9,weight:.bold)).tracking(1.6).foregroundStyle(Color.esMuted);Spacer();Image(systemName:"slider.horizontal.3").foregroundStyle(Color.esMuted).font(.system(size:12)) }
                    HStack(spacing:12) { Image(systemName:tool.symbol).font(.system(size:19)).foregroundStyle(Color.esAccent).frame(width:40,height:40).background(Color.esAccent.opacity(0.1),in:RoundedRectangle(cornerRadius:11));VStack(alignment:.leading,spacing:4) { Text(tool.rawValue).font(.system(size:14,weight:.semibold));Text("Outil d’annotation").font(.system(size:10)).foregroundStyle(Color.esMuted) } }
                    Divider().overlay(.white.opacity(0.03))
                    VStack(alignment:.leading,spacing:13) { Text("Couleur").font(.system(size:11,weight:.medium));HStack(spacing:9) { ForEach(palette.indices,id:\.self) { i in Button { selectedColor=i;controller.canvas.color=NSColor(palette[i]) } label: { Circle().fill(palette[i]).frame(width:20,height:20).padding(3).overlay(Circle().stroke(selectedColor == i ? Color.white:Color.clear,lineWidth:1.4)) }.buttonStyle(HoverButtonStyle()).accessibilityLabel(["Orange","Lavande","Menthe","Jaune","Blanc","Anthracite"][i]) } } }.opacity(tool == .redact ? 0.3:1).disabled(tool == .redact)
                    VStack(alignment:.leading,spacing:12) { HStack { Text("Épaisseur");Spacer();Text("\(Int(stroke)) px").foregroundStyle(Color.esMuted).monospacedDigit() }.font(.system(size:11));Slider(value:$stroke,in:2...18,step:1).tint(.esAccent).onChange(of:stroke) { _,v in controller.canvas.strokeWidth=v } }
                    VStack(alignment:.leading,spacing:9) { Label(tool == .redact ? "Masquage définitif à l’export":"Une image, plusieurs idées",systemImage:tool == .redact ? "lock.shield":"lightbulb").font(.system(size:10,weight:.medium));Text(tool == .redact ? "L’aplat noir remplace les pixels masqués dans l’image exportée.":"Tes annotations sont superposées à l’image. Annule librement avant d’exporter.").font(.system(size:10)).foregroundStyle(Color.esMuted).lineSpacing(4) }.padding(14).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                    Spacer()
                    VStack(alignment:.leading,spacing:15) { HStack { Text("Annotations").font(.system(size:11));Spacer();Text("\(count)").font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(Color.esMuted).padding(.horizontal,7).padding(.vertical,4).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:5)) };Button { controller.clearMarks();count=0 } label: { Label("Effacer les annotations",systemImage:"trash").font(.system(size:11)).foregroundStyle(Color.esMuted) }.buttonStyle(HoverButtonStyle()).disabled(count == 0);Divider();Button { controller.extract() } label: { HStack { Image(systemName:"text.viewfinder");Text("Extraire le texte");Spacer();Image(systemName:"arrow.up.right").font(.system(size:9)) }.font(.system(size:11)).foregroundStyle(Color.esMuted) }.buttonStyle(HoverButtonStyle()) }
                }.padding(22).frame(width:240).background(Color.esSidebar)
            }
        }.background(Color.esBackground).overlay(alignment:.bottom) { if !notice.isEmpty { Label(notice,systemImage:"checkmark.circle.fill").font(.system(size:12,weight:.medium)).foregroundStyle(.white).padding(.horizontal,18).padding(.vertical,12).background(Color.esSurface,in:Capsule()).overlay(Capsule().stroke(.white.opacity(0.1))).shadow(color:.black.opacity(0.3),radius:15,y:5).padding(.bottom,55).transition(.opacity.combined(with:.move(edge:.bottom))) } }
        .onAppear { controller.canvas.color=NSColor(palette[0]);controller.canvas.changed={ count=controller.canvas.marks.count } }
    }
    func notify(_ text:String) { withAnimation(.easeOut(duration:0.2)) { notice=text };DispatchQueue.main.asyncAfter(deadline:.now()+2.5) { withAnimation { notice="" } } }
}

final class CenteredClipView:NSClipView {
    override func constrainBoundsRect(_ proposedBounds:NSRect)->NSRect {
        var result=super.constrainBoundsRect(proposedBounds)
        if let doc=documentView {
            if doc.frame.width < result.width { result.origin.x=(doc.frame.width-result.width)/2 }
            if doc.frame.height < result.height { result.origin.y=(doc.frame.height-result.height)/2 }
        }
        return result
    }
}

struct HoverButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View { HoverButtonContent(configuration:configuration) }
}
private struct HoverButtonContent:View {
    let configuration:ButtonStyleConfiguration
    @State private var hovered=false
    var body:some View { configuration.label.brightness(hovered ? 0.06:0).opacity(configuration.isPressed ? 0.7:1).contentShape(Rectangle()).onHover { hovered=$0 }.animation(.easeOut(duration:0.12),value:hovered) }
}

struct CaptureToast:View {
    let title:String;let detail:String;var success=true
    var body:some View { HStack(spacing:14) { Image(systemName:success ? "checkmark.circle.fill":"text.viewfinder").font(.system(size:24)).foregroundStyle(Color.esAccent);VStack(alignment:.leading,spacing:6) { Text(title).font(.system(size:13,weight:.semibold));Text(detail).font(.system(size:11)).foregroundStyle(Color.esMuted) };Spacer(minLength:0) }.padding(20).background(Color.esSurface,in:RoundedRectangle(cornerRadius:15)).overlay(RoundedRectangle(cornerRadius:15).stroke(.white.opacity(0.1))).padding(2) }
}

import SwiftUI
import AppKit
import AVKit

final class VideoEditorController:NSWindowController,NSWindowDelegate {
    let model:VideoEditorModel
    init(url:URL,owner:AppDelegate) {
        model=VideoEditorModel(url:url,owner:owner)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1380,height:920),styleMask:[.titled,.closable,.resizable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init(window:window);window.title="EasyShoot · Montage vidéo";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.backgroundColor=NSColor(Color.esBackground);window.minSize=NSSize(width:1100,height:780);window.center();window.isReleasedWhenClosed=false;window.delegate=self
        window.contentView=NSHostingView(rootView:VideoEditorView(model:model).preferredColorScheme(.dark))
    }
    required init?(coder:NSCoder) {fatalError()}
    func windowShouldClose(_ sender:NSWindow)->Bool {
        if model.exporting {model.errorMessage="Annule l’export ou attends sa fin avant de fermer l’éditeur.";return false}
        if model.hasUnexportedChanges {
            let alert=NSAlert();alert.messageText="Fermer le montage ?";alert.informativeText="L’original est conservé. Les modifications non exportées seront perdues.";alert.addButton(withTitle:"Continuer le montage");alert.addButton(withTitle:"Fermer")
            return alert.runModal() == .alertSecondButtonReturn
        }
        return true
    }
    func windowWillClose(_ notification:Notification) {model.close();model.owner.videoEditors.removeAll{$0 === self}}
}
struct MoviePlayerHost:NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context)->AVPlayerView {let view=AVPlayerView();view.player=player;view.controlsStyle = .none;view.videoGravity = .resizeAspect;view.showsFullScreenToggleButton=false;return view}
    func updateNSView(_ view:AVPlayerView,context:Context) {if view.player !== player {view.player=player}}
}
struct VideoEditorView:View {
    @ObservedObject var model:VideoEditorModel
    @State private var inspector=0
    var body:some View {
        VStack(spacing:0) {
            header
            Rectangle().fill(.white.opacity(0.07)).frame(height:1)
            HStack(spacing:0) {
                VStack(spacing:0) {
                    ZStack {
                        Color(red:0.04,green:0.045,blue:0.06)
                        MoviePlayerHost(player:model.player).padding(30)
                        if model.loading {VStack(spacing:12) {ProgressView();Text("Préparation de la vidéo…").font(.system(size:12)).foregroundStyle(Color.esMuted)}.padding(24).background(Color.esSurface,in:RoundedRectangle(cornerRadius:15))}
                        if model.previewUpdating && !model.loading {VStack {HStack {Spacer();Label("Actualisation",systemImage:"arrow.triangle.2.circlepath").font(.system(size:10)).padding(8).background(.black.opacity(0.6),in:Capsule())};Spacer()}.padding(14)}
                    }
                    playback
                    timeline
                }
                Rectangle().fill(.white.opacity(0.07)).frame(width:1)
                inspectorView.frame(width:282).background(Color.esSidebar)
            }
        }.background(Color.esBackground).task {await model.load()}
        .alert("EasyShoot",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0 {model.errorMessage=nil}})) {Button("OK") {model.errorMessage=nil}} message:{Text(model.errorMessage ?? "")}
        .overlay {if model.exporting {exportOverlay}}
    }
    var header:some View {
        HStack(spacing:14) {
            Image(systemName:"film.stack").font(.system(size:20)).foregroundStyle(Color.esAccent).frame(width:40,height:40).background(Color.esAccent.opacity(0.1),in:RoundedRectangle(cornerRadius:11))
            VStack(alignment:.leading,spacing:5) {Text("Montage vidéo").font(.system(size:16,weight:.semibold));Text(model.url.lastPathComponent).font(.system(size:10)).foregroundStyle(Color.esMuted).lineLimit(1).truncationMode(.middle)}
            Spacer()
            Label("Original conservé",systemImage:"checkmark.shield").font(.system(size:10)).foregroundStyle(Color.esMuted)
            Button {model.undo()} label:{Image(systemName:"arrow.uturn.backward").font(.system(size:14)).frame(width:34,height:34)}.buttonStyle(HoverButtonStyle()).disabled(model.undoCount == 0 || model.exporting).keyboardShortcut("z",modifiers:.command).help("Annuler la dernière modification")
            ActionButton(title:"Réinitialiser",symbol:"arrow.counterclockwise") {model.reset()}.disabled(model.loading || model.exporting)
            ActionButton(title:"Exporter le MP4",symbol:"square.and.arrow.up",primary:true) {model.export()}.disabled(model.loading || model.exporting || model.previewUpdating || model.state.clips.isEmpty).keyboardShortcut("e",modifiers:.command)
        }.padding(.horizontal,24).padding(.top,42).padding(.bottom,19)
    }
    var playback:some View {
        HStack(spacing:16) {
            Button {model.seek(0)} label:{Image(systemName:"backward.end.fill").font(.system(size:12)).frame(width:25,height:30)}.buttonStyle(HoverButtonStyle()).help("Revenir au début")
            Button {model.playPause()} label:{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.system(size:13)).foregroundStyle(Color.esAccent).frame(width:35,height:32).background(Color.esAccent.opacity(0.1),in:RoundedRectangle(cornerRadius:8))}.buttonStyle(HoverButtonStyle()).keyboardShortcut(.space,modifiers:[]).disabled(model.loading || model.previewUpdating)
            Text(VideoEditorModel.clock(model.time)).font(.system(size:11,weight:.medium,design:.monospaced));Text("/ \(VideoEditorModel.clock(model.duration))").font(.system(size:11,design:.monospaced)).foregroundStyle(Color.esMuted)
            Spacer()
            Text("\(Int(model.outputSize.width)) × \(Int(model.outputSize.height)) · 30 fps").font(.system(size:10,design:.monospaced)).foregroundStyle(Color.esMuted)
        }.padding(.horizontal,24).frame(height:56).background(Color.esSidebar)
    }
    var timeline:some View {
        VStack(alignment:.leading,spacing:15) {
            HStack {Text("TIMELINE").font(.system(size:9,weight:.bold)).tracking(1.5).foregroundStyle(Color.esMuted);Text("\(model.state.clips.count) segment\(model.state.clips.count>1 ? "s":"")").font(.system(size:10)).foregroundStyle(Color.esMuted);Spacer();Button {model.split()} label:{Label("Diviser ici",systemImage:"scissors").font(.system(size:11,weight:.medium))}.buttonStyle(HoverButtonStyle()).disabled(model.loading || model.exporting || !model.canSplit).keyboardShortcut("b",modifiers:.command)}
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    HStack(spacing:1) {ForEach(Array(model.thumbnails.enumerated()),id:\.offset) {_,image in Image(nsImage:image).resizable().scaledToFill().frame(width:max(1,geometry.size.width/CGFloat(max(1,model.thumbnails.count))),height:56).clipped()}}.clipShape(RoundedRectangle(cornerRadius:7))
                    RoundedRectangle(cornerRadius:7).fill(.black.opacity(0.15))
                    Rectangle().fill(Color.esAccent).frame(width:2).offset(x:geometry.size.width*min(1,max(0,model.time/max(0.001,model.duration))))
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged {value in model.seek(Double(min(1,max(0,value.location.x/geometry.size.width)))*model.duration)})
            }.frame(height:56)
            Slider(value:Binding(get:{min(model.time,max(0.001,model.duration))},set:{model.seek($0)}),in:0...max(0.001,model.duration)).tint(.esAccent).accessibilityLabel("Tête de lecture")
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {ForEach(Array(model.state.clips.enumerated()),id:\.element.id) {index,clip in Button {model.select(clip.id)} label:{HStack(spacing:8) {Text(String(format:"%02d",index+1)).font(.system(size:10,weight:.bold,design:.monospaced));Text(VideoEditorModel.clock(clip.duration)).font(.system(size:10,design:.monospaced));if clip.speed != 1 {Text("\(clip.speed, specifier:"%.2g")×").font(.system(size:9))}}.padding(.horizontal,13).frame(height:34).foregroundStyle(model.selected == clip.id ? Color.esAccent:Color.esMuted).background(model.selected == clip.id ? Color.esAccent.opacity(0.12):Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).stroke(model.selected == clip.id ? Color.esAccent.opacity(0.6):Color.clear))}.buttonStyle(HoverButtonStyle())}}
            }
            HStack(spacing:16) {
                Button {model.moveSelected(-1)} label:{Label("Avancer",systemImage:"arrow.left")}.help("Déplacer le segment avant le précédent").disabled(!model.canMoveEarlier)
                Button {model.moveSelected(1)} label:{Label("Reculer",systemImage:"arrow.right")}.help("Déplacer le segment après le suivant").disabled(!model.canMoveLater)
                Spacer()
                Button {model.removeSelected()} label:{Label("Supprimer le segment",systemImage:"trash")}.disabled(model.state.clips.count<=1)
            }.buttonStyle(HoverButtonStyle()).font(.system(size:10)).foregroundStyle(Color.esMuted)
        }.padding(22).background(Color.esBackground).disabled(model.loading || model.exporting)
    }
    var inspectorView:some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text("PROPRIÉTÉS DU MONTAGE").font(.system(size:9,weight:.bold)).tracking(1.3).foregroundStyle(Color.esMuted)
                    Picker("Outil",selection:$inspector) {Text("Coupe").tag(0);Text("Cadrage").tag(1);Text("Audio").tag(2)}.pickerStyle(.segmented).labelsHidden()
                    if inspector == 0 {cutInspector}
                    else if inspector == 1 {cropInspector}
                    else {audioInspector}
                }.padding(23).frame(maxWidth:.infinity,alignment:.leading)
            }
            Divider()
            VStack(alignment:.leading,spacing:10) {
                Text("Export MP4").font(.system(size:12,weight:.semibold))
                Picker("Qualité",selection:Binding(get:{model.state.quality},set:{value in model.change{$0.quality=value}})) {ForEach(VideoQuality.allCases) {Text($0.rawValue).tag($0)}}.labelsHidden()
                Text("\(VideoEditorModel.clock(model.duration)) · \(Int(model.outputSize.width)) × \(Int(model.outputSize.height)) px").font(.system(size:10,design:.monospaced)).foregroundStyle(Color.esMuted)
                Text(model.exportNotice.isEmpty ? "Le montage s’enregistre dans la bibliothèque. Tu pourras ensuite le copier ou choisir un autre dossier.":model.exportNotice).font(.system(size:10)).foregroundStyle(Color.esMuted).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
            }.padding(23)
        }.disabled(model.loading || model.exporting)
    }
    var cutInspector:some View {
        VStack(alignment:.leading,spacing:19) {
            Label("Segment sélectionné",systemImage:"scissors").font(.system(size:13,weight:.semibold))
            if let clip=model.selectedClip {
                trimControl("Début dans la source",value:$model.trimStart,range:0...max(0.05,model.sourceDuration-0.05))
                trimControl("Fin dans la source",value:$model.trimEnd,range:0.05...max(0.05,model.sourceDuration))
                ActionButton(title:"Appliquer la coupe",symbol:"checkmark",primary:true) {model.applyTrim()}.disabled(model.trimEnd-model.trimStart<0.05)
                Divider()
                Text("Vitesse du segment").font(.system(size:11,weight:.medium))
                Picker("Vitesse",selection:Binding(get:{clip.speed},set:{value in let id=clip.id;model.change {s in if let i=s.clips.firstIndex(where:{$0.id == id}) {s.clips[i].speed=value}}})) {ForEach([0.25,0.5,1,1.5,2,4],id:\.self) {Text("\($0,specifier:"%.2g")×").tag($0)}}.labelsHidden()
                tip("Supprimer un passage","Place la tête de lecture avant et après le passage, divise deux fois, puis supprime le segment central.")
            }
        }
    }
    func trimControl(_ title:String,value:Binding<Double>,range:ClosedRange<Double>)->some View {VStack(alignment:.leading,spacing:8) {HStack {Text(title).font(.system(size:10)).foregroundStyle(Color.esMuted);Spacer();TextField("Secondes",value:value,format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width:67).font(.system(size:11,design:.monospaced));Text("s").font(.system(size:10)).foregroundStyle(Color.esMuted)};Slider(value:value,in:range).tint(.esAccent).accessibilityLabel(title)}}
    var cropInspector:some View {
        VStack(alignment:.leading,spacing:20) {
            Label("Recadrer la vidéo",systemImage:"crop").font(.system(size:13,weight:.semibold))
            Picker("Format",selection:Binding(get:{model.state.framing},set:{value in model.change{$0.framing=value}})) {ForEach(VideoFraming.allCases) {Text($0.rawValue).tag($0)}}
            Text("Position horizontale").font(.system(size:11))
            Slider(value:Binding(get:{model.state.cropX},set:{value in model.change{$0.cropX=value}}),in:0...1,onEditingChanged:model.gesture).tint(.esAccent).disabled(!model.canPanX).accessibilityLabel("Position horizontale du cadrage")
            Text("Position verticale").font(.system(size:11))
            Slider(value:Binding(get:{model.state.cropY},set:{value in model.change{$0.cropY=value}}),in:0...1,onEditingChanged:model.gesture).tint(.esAccent).disabled(!model.canPanY).accessibilityLabel("Position verticale du cadrage")
            tip("Aperçu fidèle","Le cadrage visible ici est celui du MP4 exporté. Le format recadre l’image sans l’étirer.")
        }
    }
    var audioInspector:some View {
        VStack(alignment:.leading,spacing:20) {
            Label("Son du montage",systemImage:"waveform").font(.system(size:13,weight:.semibold))
            if model.hasAudio {Toggle("Retirer la piste audio",isOn:Binding(get:{model.state.muted},set:{value in model.change{$0.muted=value}})).font(.system(size:11)).tint(.esAccent);HStack {Text("Volume");Spacer();Text("\(Int(model.state.volume*100)) %").monospacedDigit()}.font(.system(size:11));Slider(value:Binding(get:{Double(model.state.volume)},set:{value in model.change{$0.volume=Float(value)}}),in:0...1,onEditingChanged:model.gesture).tint(.esAccent).disabled(model.state.muted).accessibilityLabel("Volume vidéo");tip("Audio synchronisé","Les coupes et changements de vitesse s’appliquent aussi au son.")}
            else {tip("Vidéo silencieuse","Ce fichier source ne contient pas de piste audio.")}
        }
    }
    func tip(_ title:String,_ detail:String)->some View {VStack(alignment:.leading,spacing:8) {Text(title).font(.system(size:10,weight:.semibold));Text(detail).font(.system(size:10)).foregroundStyle(Color.esMuted).lineSpacing(4).fixedSize(horizontal:false,vertical:true)}.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))}
    var exportOverlay:some View {
        ZStack {Color.black.opacity(0.55);VStack(spacing:18) {Image(systemName:"square.and.arrow.up").font(.system(size:25)).foregroundStyle(Color.esAccent);Text("Export du montage").font(.system(size:18,weight:.semibold));ProgressView(value:Double(model.exportProgress)).tint(.esAccent).frame(width:280);Text("\(Int(model.exportProgress*100)) % · Ton original reste intact.").font(.system(size:11)).foregroundStyle(Color.esMuted);ActionButton(title:"Annuler l’export",symbol:"xmark") {model.cancelExport()}}.padding(32).background(Color.esSurface,in:RoundedRectangle(cornerRadius:20))}
    }
}

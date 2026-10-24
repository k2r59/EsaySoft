import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum StudioChrome {
    private static func adaptive(_ light:Double,_ dark:Double)->Color {
        Color(nsColor:NSColor(name:nil) { appearance in NSColor(white:appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark : light,alpha:1) })
    }
    static let panel = adaptive(0.94,0.145)
    static let toolbar = adaptive(0.90,0.19)
    static let workspace = adaptive(0.82,0.105)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let border = Color.primary.opacity(0.12)
}
struct StudioButtonStyle:ButtonStyle {
    var selected = false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.contentShape(Rectangle())
            .background(selected ? Color.accentColor : configuration.isPressed ? Color.primary.opacity(0.15) : Color.clear,in:RoundedRectangle(cornerRadius:5))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.75:1)
    }
}
struct AnnotationView: View {
    @ObservedObject var model:AnnotationModel
    let cancel:()->Void
    let save:(Bool,Bool)->Void
    var open:(()->Void)? = nil
    var copy:(()->Void)? = nil
    var export:(()->Void)? = nil
    var pin:(()->Void)? = nil
    var dragProvider:(()->NSItemProvider)? = nil
    var appName = "EasyPaste"
    var allowReplacement = true
    @FocusState private var textFocused:Bool
    @State private var presets:[SavedBackdrop] = []
    @Environment(\.displayScale) private var displayScale
    private var style:Binding<AnnotationBackdrop> { Binding(get:{model.snapshot.backdrop},set:{model.changeBackdrop($0)}) }
    var body:some View {
        VStack(spacing:0) {
            toolbar
            Divider()
            HStack(spacing:0) {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if model.showingBackdrop { backdropInspector }
                        else { toolInspector }
                    }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                }.frame(width:280).background(StudioChrome.panel)
                Divider()
                ZStack(alignment:.top) {
                    AnnotationCanvas(model:model)
                    if model.textPoint != nil { textEntry.padding(16) }
                    if model.loadingNative { ProgressView("Pixels d’origine…").padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:9)).padding(16) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }.frame(maxHeight:.infinity).disabled(model.saving)
            Divider()
            footer
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red).font(.system(size:13)).padding(8).frame(maxWidth:.infinity).background(StudioChrome.panel) }
        }.chromeGlass(base: StudioChrome.panel, radius: 16).foregroundStyle(StudioChrome.ink).tint(.accentColor)
            .environment(\.locale,Locale(identifier:"fr_FR"))
            .task {presets = await Task.detached(priority:.utility) {SavedBackdrop.load()}.value}
            .task(id:model.zoom != nil) {
                guard model.zoom != nil, model.image.width < Int(model.size.width) else { model.nativeImage=nil;model.loadingNative=false;return }
                model.loadingNative=true
                let data=model.data
                let worker=Task.detached(priority:.userInitiated) { try AnnotationRaster.decode(data).0 }
                do {
                    let image=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                    guard !Task.isCancelled else{return};model.nativeImage=image;model.loadingNative=false
                } catch { if !Task.isCancelled { model.error=error.localizedDescription;model.loadingNative=false } }
            }
            .overlay(alignment:.bottom) {
                if !model.notice.isEmpty { Text(model.notice).font(.system(size:12)).padding(.horizontal,16).padding(.vertical,9).background(.regularMaterial,in:Capsule()).padding(.bottom,48).allowsHitTesting(false) }
            }
    }
    private var toolbar:some View {
        HStack(spacing:3) {
            Color.clear.frame(width:64,height:24) // Space for native window controls.
            if let open { icon("Ouvrir une image","photo.badge.plus",action:open) }
            icon("Fond", "photo.on.rectangle", selected:model.showingBackdrop) { model.showingBackdrop=true;model.select(nil);model.draft=nil }
            Divider().frame(height:21).padding(.horizontal,3)
            ForEach(AnnotationTool.allCases,id:\.self) { tool in
                icon(tool.title,tool.icon,selected:!model.showingBackdrop && model.tool == tool) { model.chooseTool(tool) }
            }
            Divider().frame(height:21).padding(.horizontal,3)
            icon("Annuler · ⌘Z","arrow.uturn.backward") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
            icon("Rétablir · ⇧⌘Z","arrow.uturn.forward") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
            Spacer(minLength:5)
            if let export { Button("Enregistrer…",action:export).controlSize(.regular).keyboardShortcut("s",modifiers:[.command,.shift]).help("Enregistrer le PNG sans fermer l’éditeur") }
            Button { if model.textPoint != nil {model.addText()};save(model.replaceOriginal,model.copyToClipboard) } label: {
                HStack(spacing:5) { if model.saving {ProgressView().controlSize(.mini)};Text("Terminé").font(.system(size:13,weight:.medium)) }.padding(.horizontal,7).frame(height:25)
            }.buttonStyle(.borderedProminent).tint(.blue).controlSize(.regular).keyboardShortcut("s",modifiers:.command)
        }.padding(.horizontal,10).frame(height:50).disabled(model.saving)
    }
    private func icon(_ title:String,_ image:String,selected:Bool=false,action:@escaping()->Void)->some View {
        Button(action:action) { Image(systemName:image).font(.system(size:15,weight:.medium)).frame(width:34,height:32) }
            .buttonStyle(StudioButtonStyle(selected:selected)).help(title).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected:[])
    }
    private var backdropInspector:some View {
        Group {
            Button { var v=style.wrappedValue;v.background="none";style.wrappedValue=v } label: {
                Text("Sans fond").font(.system(size:15,weight:.medium)).frame(maxWidth:.infinity).frame(height:30)
            }.buttonStyle(StudioButtonStyle(selected:!style.wrappedValue.enabled)).background(Color.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:5))
            swatches("Dégradés",BackdropPreset.gradients)
            VStack(alignment:.leading,spacing:7) {
                caption("Fonds d’écran")
                HStack(spacing:7) {
                    ForEach(BackdropPreset.wallpapers) { preset in swatch(preset) }
                    Button(action:loadBackground) { Image(systemName:"plus").font(.system(size:12)).frame(width:36,height:36).background(Color.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:6)) }
                        .buttonStyle(StudioButtonStyle(selected:style.wrappedValue.background == "custom")).help("Choisir une image de fond…").accessibilityLabel("Choisir une image de fond")
                }
            }
            swatches("Floutés",BackdropPreset.blurred)
            VStack(alignment:.leading,spacing:7) {
                caption("Couleur unie")
                LazyVGrid(columns:Array(repeating:GridItem(.fixed(22),spacing:8),count:8),spacing:6) {
                    ForEach(BackdropPreset.solids,id:\.self) { hex in
                        let id="solid-"+String(hex,radix:16)
                        Button { var v=style.wrappedValue;v.background=id;style.wrappedValue=v } label: {
                            Circle().fill(Color(cgColor:BackdropPreset.color(hex))).frame(width:19,height:19).overlay(Circle().stroke(Color.primary.opacity(0.2),lineWidth:0.5)).padding(2)
                                .overlay(Circle().stroke(style.wrappedValue.background == id ? Color.accentColor:.clear,lineWidth:2))
                        }.buttonStyle(StudioButtonStyle()).accessibilityLabel("Fond #"+String(hex,radix:16)).help("#"+String(hex,radix:16).uppercased())
                    }
                    ColorPicker("Couleur personnalisée",selection:Binding(get:{ customColor },set:{ setCustomColor($0) }),supportsOpacity:false).labelsHidden().frame(width:22,height:22).clipped().overlay(Circle().fill(AngularGradient(colors:[.red,.yellow,.green,.cyan,.blue,.purple,.red],center:.center)).frame(width:19,height:19).allowsHitTesting(false)).help("Choisir une autre couleur")
                }
            }
            Divider()
            VStack(spacing:13) {
                setting("Marge",\.padding,range:0...320)
                HStack(alignment:.bottom,spacing:9) {
                    setting("Retrait",\.inset,range:0...120)
                    Toggle("Équilibrage auto",isOn:Binding(get:{style.wrappedValue.autoBalance},set:{v in var s=style.wrappedValue;s.autoBalance=v;style.wrappedValue=s})).toggleStyle(.checkbox).font(.system(size:12)).fixedSize().padding(.bottom,4)
                }.help("Retirer les marges uniformes autour du contenu, sans modifier l’original")
                HStack(alignment:.top,spacing:12) {
                    setting("Ombre",\.shadow,range:0...100)
                    setting("Arrondi",\.corners,range:0...80)
                }
                HStack(alignment:.top,spacing:20) {
                    VStack(alignment:.leading,spacing:7) {
                        caption("Alignement")
                        LazyVGrid(columns:Array(repeating:GridItem(.fixed(25),spacing:4),count:3),spacing:3) {
                            ForEach(0..<9) { i in
                                Button { var v=style.wrappedValue;v.alignment=i;style.wrappedValue=v } label: {
                                    Image(systemName:["arrow.up.left","arrow.up","arrow.up.right","arrow.left","dot.square","arrow.right","arrow.down.left","arrow.down","arrow.down.right"][i]).font(.system(size:11,weight:.semibold)).frame(width:25,height:25)
                                }.buttonStyle(StudioButtonStyle(selected:style.wrappedValue.alignment == i)).accessibilityLabel(["En haut à gauche","En haut","En haut à droite","À gauche","Centré","À droite","En bas à gauche","En bas","En bas à droite"][i])
                            }
                        }
                    }
                    VStack(alignment:.leading,spacing:8) {
                        caption("Proportions")
                        Picker("Proportions",selection:Binding(get:{style.wrappedValue.ratio},set:{v in var s=style.wrappedValue;s.ratio=v;style.wrappedValue=s})) {
                            ForEach(AnnotationBackdrop.ratios,id:\.self) { Text($0).tag($0) }
                        }.labelsHidden().controlSize(.regular).frame(width:108)
                    }
                }
            }.disabled(!style.wrappedValue.enabled)
            Divider()
            HStack {
                Menu("Préréglages") {
                    Button("Enregistrer ce style…",action:savePreset).disabled(!style.wrappedValue.enabled)
                    if !presets.isEmpty { Divider() }
                    ForEach(presets) { preset in Button(preset.name) { applyPreset(preset) } }
                    if !presets.isEmpty { Divider();Button("Supprimer les styles enregistrés") { presets=[];SavedBackdrop.store(presets) } }
                }.menuStyle(.borderlessButton).font(.system(size:13))
                Spacer()
                Button { style.wrappedValue=AnnotationBackdrop() } label: { Image(systemName:"arrow.counterclockwise").frame(width:25,height:25) }.buttonStyle(StudioButtonStyle()).help("Réinitialiser le fond").accessibilityLabel("Réinitialiser le fond")
            }
        }
    }
    private func setting(_ title:String,_ path:WritableKeyPath<AnnotationBackdrop,Double>,range:ClosedRange<Double>)->some View {
        VStack(spacing:3) {
            HStack { caption(title);Spacer(minLength:0);TextField(title,value:Binding(get:{style.wrappedValue[keyPath:path]},set:{v in var s=style.wrappedValue;s[keyPath:path]=min(range.upperBound,max(range.lowerBound,v.isFinite ? v:range.lowerBound));style.wrappedValue=s}),format:.number.precision(.fractionLength(0))).textFieldStyle(.plain).multilineTextAlignment(.trailing).font(.system(size:12).monospacedDigit()).frame(width:34).accessibilityLabel(title) }
            Slider(value:Binding(get:{style.wrappedValue[keyPath:path]},set:{v in var s=style.wrappedValue;s[keyPath:path]=v.rounded();style.wrappedValue=s}),in:range,onEditingChanged:{editing in if editing {model.beginStyleEdit()} else {model.endStyleEdit()} }).controlSize(.regular).accessibilityLabel(title)
        }
    }
    private func caption(_ text:String)->some View { Text(text).font(.system(size:12,weight:.medium)).foregroundStyle(StudioChrome.muted) }
    private func swatches(_ title:String,_ values:[BackdropPreset])->some View {
        VStack(alignment:.leading,spacing:7) {
            caption(title)
            LazyVGrid(columns:Array(repeating:GridItem(.fixed(36),spacing:8),count:5),alignment:.leading,spacing:7) { ForEach(values) {swatch($0)} }
        }
    }
    private func swatch(_ preset:BackdropPreset)->some View {
        Button { var value=style.wrappedValue;value.background=preset.id;style.wrappedValue=value } label: {
            RoundedRectangle(cornerRadius:6).fill(LinearGradient(colors:preset.colors.map {Color(cgColor:BackdropPreset.color($0))},startPoint:.bottomLeading,endPoint:.topTrailing)).frame(width:36,height:36)
                .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(style.wrappedValue.background == preset.id ? Color.accentColor:Color.primary.opacity(0.12),lineWidth:style.wrappedValue.background == preset.id ? 2.5:0.5))
        }.buttonStyle(StudioButtonStyle()).help(preset.name).accessibilityLabel("Fond "+preset.name).accessibilityAddTraits(style.wrappedValue.background == preset.id ? .isSelected:[])
    }
    private var customColor:Color {
        let id=style.wrappedValue.background
        return id.hasPrefix("solid-") ? Color(cgColor:BackdropPreset.color(UInt32(id.dropFirst(6),radix:16) ?? 0xFFFFFF)):.white
    }
    private func setCustomColor(_ color:Color) {
        guard let rgb=NSColor(color).usingColorSpace(.sRGB) else{return}
        let hex=UInt32((rgb.redComponent*255).rounded())<<16 | UInt32((rgb.greenComponent*255).rounded())<<8 | UInt32((rgb.blueComponent*255).rounded())
        var s=style.wrappedValue;s.background="solid-"+String(hex,radix:16);style.wrappedValue=s
    }
    private func loadBackground() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.png,.jpeg,.heic,.tiff];panel.canChooseDirectories=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        Task {
            do {
                let image=try await Task.detached(priority:.userInitiated) { let data=try Data(contentsOf:url);return try AnnotationRaster.decode(data,maxPixels:4096).0 }.value
                var s=style.wrappedValue;s.background="custom";model.setBackground(image,style:s)
            } catch {model.error=error.localizedDescription}
        }
    }
    private func savePreset() {
        let alert=NSAlert();alert.messageText="Nom du préréglage";let field=NSTextField(frame:CGRect(x:0,y:0,width:230,height:24));field.placeholderString="Mon style";alert.accessoryView=field;alert.addButton(withTitle:"Enregistrer");alert.addButton(withTitle:"Annuler");alert.window.initialFirstResponder=field
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        let name=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else{return}
        var saved=style.wrappedValue
        saved.padding=saved.padding.rounded()
        let image=model.customBackground
        model.saving=true
        Task {
            do {
                let data=try await Task.detached(priority:.utility) {try image.map {try AnnotationRaster.png($0)}}.value
                presets.append(SavedBackdrop(name:String(name.prefix(40)),style:saved,image:data));presets=Array(presets.suffix(20));SavedBackdrop.store(presets)
                model.saving=false
            } catch {model.saving=false;model.error=error.localizedDescription}
        }
    }
    private func applyPreset(_ preset:SavedBackdrop) {
        model.saving=true
        Task {
            do {
                let image=try await Task.detached(priority:.userInitiated) {try preset.image.map {try AnnotationRaster.decode($0,maxPixels:4096).0}}.value
                model.saving=false;model.setBackground(image,style:preset.style)
            } catch {model.saving=false;model.error=error.localizedDescription}
        }
    }
    private var toolInspector:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Image(systemName:model.activeTool.icon);Text(model.activeTool.title).fontWeight(.semibold) }.font(.system(size:12))
            if ![AnnotationTool.selection,.crop,.redact].contains(model.activeTool) {
                VStack(alignment:.leading,spacing:9) {
                    caption("Couleur")
                    HStack(spacing:7) { ForEach(AnnotationColor.allCases,id:\.self) {color in
                        Button {model.changeColor(color)} label: {
                            Circle().fill(Color(cgColor:color.cgColor)).frame(width:19,height:19).padding(2).overlay(Circle().stroke(model.color == color ? Color.accentColor:.clear,lineWidth:2))
                        }.buttonStyle(StudioButtonStyle()).accessibilityLabel(color.title).help(color.title)
                    } }
                }
                VStack(spacing:6) {
                    HStack {caption(model.activeTool == .text ? "Taille du texte":"Épaisseur");Spacer();Text("\(Int(model.activeTool == .text ? max(14,model.width*6):model.width)) px").font(.system(size:12).monospacedDigit()).foregroundStyle(StudioChrome.muted)}
                    Slider(value:Binding(get:{model.width},set:{model.changeWidth($0.rounded())}),in:1...48,onEditingChanged:{editing in if editing {model.beginStyleEdit()} else {model.endStyleEdit()}}).controlSize(.small).accessibilityLabel("Épaisseur")
                }
            }
            if model.activeTool == .arrow {
                HStack(spacing:5) { ForEach(AnnotationArrowhead.allCases,id:\.self) {head in
                    icon(head.title,head.icon,selected:model.arrowhead == head) {model.changeArrowhead(head)}
                } }
            }
            if model.activeTool == .redact { Text("Masquage opaque à l’export.").font(.system(size:13)).foregroundStyle(StudioChrome.muted) }
            if model.activeTool == .crop {
                Text("Trace la zone à conserver.").font(.system(size:13)).foregroundStyle(StudioChrome.muted)
                if model.snapshot.crop != nil {Button("Retirer le recadrage") {model.removeCrop()}.controlSize(.small)}
            }
            Divider()
            HStack {caption("Annotations");Spacer();Text("\(model.snapshot.marks.count)").font(.system(size:12).monospacedDigit()).foregroundStyle(StudioChrome.muted)}
            LazyVStack(spacing:3) {
                ForEach(model.snapshot.marks) {mark in
                    Button {model.select(mark.id)} label: {
                        HStack(spacing:7) {Image(systemName:mark.tool.icon).frame(width:16);Text(mark.tool == .text ? mark.text:mark.tool.title).lineLimit(1);Spacer(minLength:0)}.font(.system(size:13)).padding(7).frame(maxWidth:.infinity)
                    }.buttonStyle(StudioButtonStyle(selected:model.selectedID == mark.id))
                }
            }
            if model.selectedMark?.tool == .text {Button("Modifier le texte…") {model.editSelectedText()}.controlSize(.small)}
            if model.selectedMark != nil {Button("Supprimer l’annotation") {model.deleteSelection()}.controlSize(.small)}
        }
    }
    private var textEntry:some View {
        HStack(spacing:8) {
            TextField("Texte…",text:$model.text).textFieldStyle(.plain).focused($textFocused).onSubmit {model.addText()}
            Button("Valider") {model.addText()}.controlSize(.small).disabled(model.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            icon("Annuler le texte","xmark") {model.textPoint=nil;model.text="";model.editingTextID=nil}
        }.padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:9)).frame(maxWidth:480).task {await Task.yield();textFocused=true}
    }
    private var footer:some View {
        HStack(spacing:9) {
            Menu {
                Button("Ajuster à la fenêtre") {model.zoom=nil}
                ForEach([25,50,75,100,150,200,400],id:\.self) {p in Button("\(p) %") {model.zoom=CGFloat(p)/100}}
            } label:{ Text(model.zoom.map {"\(Int($0*100)) %"} ?? "Ajuster").font(.system(size:12).monospacedDigit()).frame(width:65,height:28) }.menuStyle(.borderlessButton).fixedSize()
            Text("\(Int(model.outputSize.width)) × \(Int(model.outputSize.height))").font(.system(size:12).monospacedDigit()).foregroundStyle(StudioChrome.muted)
            Spacer()
            if let dragProvider {
                Text("Glisse-moi").font(.system(size:12,weight:.medium)).padding(.horizontal,13).frame(height:23).background(Color.primary.opacity(0.08),in:RoundedRectangle(cornerRadius:4)).contentShape(Rectangle()).onDrag {dragProvider()}.help("Glisser le PNG vers une autre application")
            }
            Spacer()
            Menu {
                Toggle("Copier avec Terminé",isOn:$model.copyToClipboard)
                if allowReplacement { Toggle("Remplacer l’originale",isOn:$model.replaceOriginal) }
            } label:{Image(systemName:"ellipsis").frame(width:25,height:25)}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Options d’enregistrement")
            icon("Fermer sans enregistrer","trash",action:cancel)
            if let pin {icon("Épingler l’image","pin",action:pin)}
            if let copy {icon("Copier l’image · ⇧⌘C","doc.on.clipboard",action:copy).keyboardShortcut("c",modifiers:[.command,.shift])}
            if let export {icon("Exporter le PNG","square.and.arrow.up",action:export)}
        }.padding(.horizontal,12).frame(height:42).disabled(model.saving)
    }
}
private struct SavedBackdrop:Codable,Identifiable {
    var id=UUID();let name:String;let style:AnnotationBackdrop;var image:Data? = nil
    private static var file:URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "AnnotationTests").appendingPathComponent("annotation-presets.json") }
    static func load()->[Self] {guard let data=try? Data(contentsOf:file) else{return []};return (try? JSONDecoder().decode([Self].self,from:data)) ?? []}
    private static let writeQueue=DispatchQueue(label:"annotation.presets",qos:.utility)
    static func store(_ value:[Self]) {
        let url=file
        writeQueue.async {
            guard let data=try? JSONEncoder().encode(value) else{return}
            try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? data.write(to:url,options:.atomic)
        }
    }
}

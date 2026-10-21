import SwiftUI

struct AnnotationView: View {
    @ObservedObject var model: AnnotationModel
    let cancel: () -> Void
    let save: (Bool, Bool) -> Void
    private var replaceOriginal: Bool { model.replaceOriginal }
    private var copyToClipboard: Bool { model.copyToClipboard }
    @FocusState private var textFocused: Bool
    @State private var showingHelp = false
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                tools.frame(width: 165)
                Rectangle().fill(Theme.border).frame(width: 1)
                workspace
                Rectangle().fill(Theme.border).frame(width: 1)
                inspector.frame(width: 218)
            }.frame(maxHeight: .infinity)
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }.background(Theme.bg).foregroundStyle(Theme.ink)
            .environment(\.locale, Locale(identifier: "fr_FR"))
            .task(id: model.zoom != nil) {
                guard model.zoom != nil, model.image.width < Int(model.size.width) else { model.nativeImage = nil; model.loadingNative = false; return }
                model.loadingNative = true
                let data = model.data
                let worker = Task.detached(priority: .userInitiated) { try ImageRaster.decode(data).0 }
                do {
                    let image = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    guard !Task.isCancelled else { return }; model.nativeImage = image; model.loadingNative = false
                } catch { if !Task.isCancelled { model.error = error.localizedDescription; model.loadingNative = false } }
            }
    }
    private var titleBar: some View {
        HStack(spacing: 13) {
            BrandMark(size: 30)
            Text("EasyPaste").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            Divider().frame(height: 29).padding(.horizontal, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text("Annoter une capture").font(.system(size: 17, weight: .semibold))
                Text("\(Int(model.size.width)) × \(Int(model.size.height)) px").font(.system(size: 11)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Spacer()
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 16) }.buttonStyle(PasteButtonStyle()).disabled(model.undoStates.isEmpty || model.saving).keyboardShortcut("z", modifiers: .command).help("Annuler · ⌘Z").accessibilityLabel("Annuler la dernière modification")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 16) }.buttonStyle(PasteButtonStyle()).disabled(model.redoStates.isEmpty || model.saving).keyboardShortcut("z", modifiers: [.command, .shift]).help("Rétablir · ⇧⌘Z").accessibilityLabel("Rétablir la modification")
            Divider().frame(height: 25).padding(.horizontal, 5)
            Text("PNG").font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 10).background(Theme.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 9)).help("Export sans perte à la résolution d’origine")
        }.padding(.horizontal, 22).padding(.top, 27).padding(.bottom, 17).background(Theme.panel)
    }
    private var tools: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    if tool == .redact { Divider().padding(.vertical, 8) }
                    Button { model.chooseTool(tool) } label: {
                        HStack(spacing: 11) {
                            Image(systemName: tool.icon).font(.system(size: 18)).frame(width: 23)
                            Text(tool.title).font(.system(size: 12, weight: model.tool == tool ? .medium : .regular)).lineLimit(1)
                            Spacer(minLength: 0)
                            if model.tool == tool { Circle().fill(Theme.mint).frame(width: 5, height: 5) }
                        }.padding(.horizontal, 10).frame(height: 42)
                            .background(model.tool == tool ? Theme.mint.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.tool == tool ? Theme.mint.opacity(0.4) : .clear))
                    }.buttonStyle(FullAreaButtonStyle()).accessibilityAddTraits(model.tool == tool ? .isSelected : [])
                }
            }.padding(11)
        }.background(Theme.panel.opacity(0.6)).disabled(model.saving)
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let fit = min(1, min(max(1, geo.size.width-40)*displayScale/model.size.width, max(1, geo.size.height-84)*displayScale/model.size.height))
                VStack(spacing: 0) {
                    AnnotationCanvas(model: model)
                        .overlay { if model.loadingNative { ProgressView("Pixels d’origine…").padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10)) } }
                        .overlay(alignment: .top) { if model.textPoint != nil { textEntry.padding(10) } }
                    zoomControls(fit: fit).frame(height: 44)
                }
            }
            if !model.error.isEmpty {
                Text(model.error).font(.system(size: 11)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).padding(.vertical, 10)
            }
        }
    }
    private var hint: String {
        switch model.tool {
        case .selection: "Clique sur une annotation pour la déplacer. Ajuste sa position avec les flèches du clavier."
        case .redact: "Dessine un rectangle sur le contenu à masquer."
        case .crop: "Dessine la zone à conserver."
        case .text: "Clique sur l’image pour placer le texte."
        default: "Glisse sur l’image pour dessiner."
        }
    }
    private var textEntry: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
            TextField("Ton texte…", text: $model.text).textFieldStyle(.plain).focused($textFocused).onSubmit { model.addText() }
            Button(model.editingTextID == nil ? "Ajouter" : "Valider") { model.addText() }.buttonStyle(PasteButtonStyle(primary: true)).disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { model.textPoint = nil; model.text = ""; model.editingTextID = nil } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.buttonStyle(FullAreaButtonStyle()).accessibilityLabel("Annuler le texte")
        }.font(.system(size: 12)).padding(10).background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border)).task { await Task.yield(); textFocused = true }
    }
    private func zoomControls(fit: CGFloat) -> some View {
        HStack(spacing: 5) {
            Button { model.zoom = max(0.1, (model.zoom ?? fit)/1.25) } label: { Image(systemName: "minus").frame(width: 30, height: 30) }.buttonStyle(FullAreaButtonStyle()).help("Réduire").accessibilityLabel("Réduire le zoom")
            Menu {
                ForEach([25, 50, 75, 100, 150, 200, 400], id: \.self) { percent in Button("\(percent) %") { model.zoom = CGFloat(percent)/100 } }
            } label: { Text("\(Int(((model.zoom ?? fit)*100).rounded())) %").monospacedDigit().frame(width: 53, height: 30).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("100 % : un pixel de l’image par pixel d’écran")
            Button { model.zoom = min(4, (model.zoom ?? fit)*1.25) } label: { Image(systemName: "plus").frame(width: 30, height: 30) }.buttonStyle(FullAreaButtonStyle()).help("Agrandir").accessibilityLabel("Agrandir le zoom")
            Divider().frame(height: 18).padding(.horizontal, 6)
            Button { model.zoom = nil } label: { Label("Ajuster", systemImage: "arrow.up.left.and.arrow.down.right").padding(.horizontal, 10).frame(height: 30) }.buttonStyle(FullAreaButtonStyle())
            Button { showingHelp.toggle() } label: { Image(systemName: "questionmark.circle").frame(width: 30, height: 30) }
                .buttonStyle(FullAreaButtonStyle()).help("Aide pour l’outil sélectionné").accessibilityLabel("Aide pour l’outil sélectionné")
                .popover(isPresented: $showingHelp) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.tool.title).fontWeight(.semibold)
                        Text(hint)
                        Text("⌘Z : annuler · ⇧⌘Z : rétablir").foregroundStyle(Theme.muted)
                    }.font(.system(size: 12)).padding(18).frame(width: 280).fixedSize(horizontal: false, vertical: true).background(Theme.panel).foregroundStyle(Theme.ink)
                }
        }.font(.system(size: 12)).padding(4).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10)).disabled(model.saving)
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.activeTool.title).font(.system(size: 20, weight: .semibold))
                    if model.activeTool == .selection { Text("Choisis une annotation").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }
                Divider()
                if ![AnnotationTool.selection, .crop, .redact].contains(model.activeTool) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Couleur").font(.system(size: 12, weight: .medium))
                        HStack(spacing: 5) {
                            ForEach(AnnotationColor.allCases, id: \.self) { color in
                                Button { model.changeColor(color) } label: {
                                    Circle().fill(Color(cgColor: color.cgColor)).frame(width: 22, height: 22)
                                        .overlay { if model.color == color { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(color == .black ? .white : .black) } }
                                        .padding(3).overlay(Circle().strokeBorder(model.color == color ? Theme.ink : .clear, lineWidth: 1.5))
                                }.buttonStyle(FullAreaButtonStyle()).help(color.title).accessibilityLabel(color.title).accessibilityAddTraits(model.color == color ? .isSelected : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.activeTool == .text ? "Taille du texte" : "Épaisseur").font(.system(size: 12, weight: .medium))
                        HStack(spacing: 10) {
                            Slider(value: Binding(get: { model.width }, set: { model.changeWidth($0.rounded()) }), in: 1...48, onEditingChanged: { editing in if editing { model.beginStyleEdit() } else { model.endStyleEdit() } }).tint(Theme.mint).accessibilityLabel(model.activeTool == .text ? "Taille du texte" : "Épaisseur")
                            Text("\(Int(model.activeTool == .text ? max(14, model.width*6) : model.width)) px").monospacedDigit().font(.system(size: 11)).frame(width: 49, height: 30).background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                if model.activeTool == .arrow {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Extrémité").font(.system(size: 12, weight: .medium))
                        HStack(spacing: 6) {
                            ForEach(AnnotationArrowhead.allCases, id: \.self) { style in
                                Button { model.changeArrowhead(style) } label: {
                                    Image(systemName: style.icon).font(.system(size: 17)).frame(maxWidth: .infinity).frame(height: 36)
                                        .foregroundStyle(model.arrowhead == style ? Theme.mint : Theme.ink)
                                        .background(model.arrowhead == style ? Theme.mint.opacity(0.12) : Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.arrowhead == style ? Theme.mint : .clear))
                                }.buttonStyle(FullAreaButtonStyle()).help(style.title).accessibilityLabel(style.title).accessibilityAddTraits(model.arrowhead == style ? .isSelected : [])
                            }
                        }
                    }
                }
                if model.activeTool == .redact { Text("Le contenu masqué sera supprimé de l’image exportée.").font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                if model.activeTool == .crop { Text("Dessine la zone à conserver.").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                Divider()
                HStack {
                    Text("Annotations").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                    Spacer(); Text("\(model.snapshot.marks.count)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                LazyVStack(spacing: 5) {
                    ForEach(model.snapshot.marks) { mark in
                        Button { model.select(mark.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: mark.tool.icon).frame(width: 20)
                                Text(mark.tool == .text ? mark.text : mark.tool.title).lineLimit(1); Spacer(minLength: 0)
                                if model.selectedID == mark.id { Circle().fill(Theme.mint).frame(width: 5, height: 5) }
                            }.font(.system(size: 12)).padding(10).frame(maxWidth: .infinity)
                                .background(model.selectedID == mark.id ? Theme.mint.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(FullAreaButtonStyle()).accessibilityAddTraits(model.selectedID == mark.id ? .isSelected : [])
                    }
                }
                if model.selectedMark != nil {
                    if model.selectedMark?.tool == .text { Button("Modifier le texte…") { model.editSelectedText() }.buttonStyle(PasteButtonStyle()) }
                    Button { model.deleteSelection() } label: { Label("Supprimer l’annotation", systemImage: "trash") }.buttonStyle(FullAreaButtonStyle(minimumSize: 30)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                if model.snapshot.crop != nil {
                    Button("Retirer le recadrage") { model.removeCrop() }.buttonStyle(PasteButtonStyle())
                }
            }.padding(17)
        }.background(Theme.panel.opacity(0.55)).disabled(model.saving)
    }
    private var footer: some View {
        HStack(spacing: 17) {
            Button("Annuler", action: cancel).buttonStyle(PasteButtonStyle()).disabled(model.saving)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 2) { saveOption("Créer une copie", replace: false); saveOption("Remplacer l’originale", replace: true) }
                    .padding(3).background(Theme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                Text(replaceOriginal ? "L’image d’origine sera remplacée." : "").font(.system(size: 11)).foregroundStyle(Theme.colors[2]).frame(height: 14)
            }
            Toggle("Copier dans le presse-papiers", isOn: $model.copyToClipboard).toggleStyle(.checkbox).font(.system(size: 11)).tint(Theme.mint).fixedSize().disabled(model.saving)
            Button { save(replaceOriginal, copyToClipboard) } label: {
                HStack(spacing: 10) { if model.saving { ProgressView().controlSize(.small) }; Text(model.saving ? "Enregistrement…" : replaceOriginal ? "Remplacer" : "Créer la copie"); Text("⌘S").opacity(0.75) }
            }.buttonStyle(PasteButtonStyle(primary: true)).disabled(model.saving || !model.dirty).keyboardShortcut("s", modifiers: .command)
        }.padding(.horizontal, 18).padding(.vertical, 16).background(Theme.panel)
    }
    private func saveOption(_ title: String, replace: Bool) -> some View {
        Button { model.replaceOriginal = replace } label: {
            Text(title).font(.system(size: 11, weight: replaceOriginal == replace ? .semibold : .regular)).padding(.horizontal, 11).frame(height: 29)
                .foregroundStyle(replaceOriginal == replace ? Theme.mint : Theme.muted)
                .background(replaceOriginal == replace ? Theme.mint.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(replaceOriginal == replace ? Theme.mint : .clear))
        }.buttonStyle(FullAreaButtonStyle()).disabled(model.saving).accessibilityAddTraits(replaceOriginal == replace ? .isSelected : [])
    }
}

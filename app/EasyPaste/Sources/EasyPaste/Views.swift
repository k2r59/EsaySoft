import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var history: History
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 212)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            if history.page == "settings" { SettingsView(history: history) }
            else { library }
        }
        .background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .modifier(HistorySheets(history: history))
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 2) { Text("EasyPaste").font(.system(size: 20, weight: .bold)); Text("GARDE LE FIL").font(.system(size: 8, weight: .semibold)).tracking(1.7).foregroundStyle(Theme.muted) }
            }.padding(.top, 35).padding(.bottom, 10)
            VStack(spacing: 5) {
                nav("Historique", "clock.arrow.circlepath", "all", count: history.total)
                nav("Favoris", "star", "pinned")
                nav("Pile de collage", "square.stack.3d.up", "stack", count: history.stack.count)
            }
            HStack { eyebrow("COLLECTIONS"); Spacer(); Button { history.showNewBoard = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Créer une collection") }
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(history.boards) { board in
                        Button { history.page = "library"; history.collection = board.id.uuidString } label: {
                            HStack(spacing: 10) { Circle().fill(Theme.colors[board.color % 4]).frame(width: 7, height: 7); Text(board.name).lineLimit(1); Spacer(); if board.shared { Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 10)) } }
                                .padding(11).background(history.collection == board.id.uuidString && history.page == "library" ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).contextMenu {
                            Button("Renommer…") { rename(board) }
                            Button("Supprimer la collection…") { confirmDelete(board) }
                        }
                    }
                    if history.boards.isEmpty { Text("Tes modèles, liens et idées,\nà garder à portée de main.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10) }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 5) {
                nav("Corbeille", "trash", "trash")
                Button { history.page = "settings" } label: { HStack(spacing: 10) { Image(systemName: "slider.horizontal.3").frame(width: 18); Text("Réglages"); Spacer() }.padding(11).background(history.page == "settings" ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) { Circle().fill(history.enabled ? Theme.mint : Theme.muted).frame(width: 6, height: 6); Text(history.enabled ? "Collecte active" : "Collecte en pause").font(.system(size: 11, weight: .medium)); Spacer(); Button { history.enabled.toggle() } label: { Image(systemName: history.enabled ? "pause.fill" : "play.fill") }.buttonStyle(.plain).disabled(history.fault || history.loading).help(history.enabled ? "Mettre en pause" : "Reprendre la collecte") }
                Text("Sur ce Mac. Rien dans le cloud.").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }.padding(13).background(Theme.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
        }.padding(.horizontal, 17).padding(.bottom, 18).background(Theme.panel.opacity(0.55)).font(.system(size: 12))
    }
    private func nav(_ title: String, _ icon: String, _ id: String, count: Int? = nil) -> some View {
        Button { history.page = "library"; history.collection = id; history.query = "" } label: {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 18); Text(title); Spacer(); if let count, count > 0 { Text("\(count)").font(.system(size: 10, design: .monospaced)).opacity(0.65) } }
                .padding(11).foregroundStyle(history.collection == id && history.page == "library" ? Theme.mint : Theme.ink.opacity(0.8))
                .background(history.collection == id && history.page == "library" ? Theme.mint.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private var title: String {
        switch history.collection { case "pinned": return "Toujours à portée."; case "stack": return "Dans le bon ordre."; case "trash": return "Une seconde chance."; case "all": return "Copie. Retrouve.\nReprends le fil."; default: return history.boards.first { $0.id.uuidString == history.collection }?.name ?? "Ta collection" }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) { Circle().fill(Theme.mint).frame(width: 5, height: 5); Text("TON ESPACE, SUR CE MAC").tracking(1.4) }.font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Button { history.openShelf?() } label: { HStack(spacing: 9) { Image(systemName: "rectangle.bottomthird.inset.filled"); Text("Barre rapide"); KeyCap(text: "⇧⌘V") } }.buttonStyle(.plain).font(.system(size: 11))
            }.padding(.top, 42).padding(.bottom, 21)
            if !history.compact { HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 13) {
                    Text(title).font(.system(size: history.collection == "all" ? 33 : 29, weight: .semibold, design: .rounded)).tracking(-1.2).lineSpacing(-1)
                    Text(history.collection == "trash" ? "Les éléments restent ici pendant 7 jours." : "Tes textes, tes images, tes bonnes idées. Toujours là.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }.padding(.leading, 25)
                Spacer(minLength: 0)
                HeroArtwork().scaleEffect(0.88).padding(.trailing, 5)
            }.frame(height: 146)
                .background(LinearGradient(colors: [Theme.panel, Theme.mint.opacity(0.055), Theme.colors[1].opacity(0.08)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(LinearGradient(colors: [.white.opacity(0.12), Theme.mint.opacity(0.12), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .padding(.bottom, 22) }
            HStack {
                Text(history.collection == "all" ? "Dernières copies" : history.collection == "pinned" ? "Tes essentiels" : "Tes éléments").font(.system(size: 16, weight: .semibold)).tracking(-0.3)
                Text("\(history.visible.count)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal, 7).padding(.vertical, 4).background(.white.opacity(0.05), in: Capsule())
                Spacer()
                CaptureMenu(history: history)
                Button { history.compact.toggle() } label: { Image(systemName: history.compact ? "rectangle.grid.2x2" : "rectangle.compress.vertical").frame(width: 16) }.buttonStyle(PasteButtonStyle()).help(history.compact ? "Vue détaillée" : "Vue compacte")
                Button { history.newSnippet = true } label: { Label("Créer un texte", systemImage: "plus") }.buttonStyle(PasteButtonStyle(primary: true))
            }.padding(.bottom, 14)
            SearchBar(history: history).padding(.bottom, 15)
            FilterBar(history: history).padding(.bottom, 19)
            if history.collection == "stack" { stackControls.padding(.bottom, 16) }
            if history.collection == "trash", !history.visible.isEmpty { HStack { Spacer(); Button("Vider la corbeille…") { confirmEmpty() }.buttonStyle(PasteButtonStyle()) }.padding(.bottom, 12) }
            if history.loading { ProgressView("Ouverture de l’historique…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if history.visible.isEmpty { ScrollView { EmptyState(history: history).frame(maxWidth: .infinity) }.frame(maxHeight: .infinity) }
            else { ClipGrid(history: history) }
            HStack(spacing: 8) {
                Image(systemName: history.fault ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(history.fault ? .orange : Theme.mint)
                Text(history.notice).lineLimit(2)
                if !history.recentlyTrashed.isEmpty { Button("Annuler") { history.undoTrash() }.buttonStyle(.plain).foregroundStyle(Theme.mint) }
                Spacer(minLength: 10)
                if !history.selection.isEmpty { Button("Copier\(history.selection.count > 1 ? " les \(history.selection.count) éléments" : "")") { Task { _ = await history.copy(history.selection) } }.buttonStyle(.plain).foregroundStyle(Theme.mint) }
                if !history.selection.isEmpty, history.collection == "trash" {
                    Button("Restaurer") { for clip in history.selection { history.restore(clip) } }.buttonStyle(.plain).foregroundStyle(Theme.mint)
                    Button("Supprimer définitivement…") { confirmPermanentDeletion(history, items: history.selection) }.buttonStyle(.plain)
                }
                if !history.selection.isEmpty, history.collection != "trash" { Button { history.trashItems(history.selection) } label: { Image(systemName: "trash").font(.system(size: 12)) }.buttonStyle(.plain).help("Supprimer la sélection").accessibilityLabel("Supprimer la sélection") }
            }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.vertical, 16)
        }.padding(.horizontal, 28)
    }
    private var stackControls: some View {
        HStack(spacing: 10) {
            Toggle("Collecter dans la pile", isOn: $history.stackRecording).toggleStyle(.switch).controlSize(.mini)
            Spacer()
            Button("Inverser") { history.stack.reverse() }.buttonStyle(PasteButtonStyle())
            Button("Copier le suivant") { Task { if let id = history.stack.first, let c = history.clips.first(where: { $0.id == id }), await history.copy([c]) { history.consumeStack([c]) } } }.buttonStyle(PasteButtonStyle(primary: true)).disabled(history.stack.isEmpty)
        }.font(.system(size: 11)).padding(12).surface()
    }
    private func rename(_ board: Pinboard) {
        let alert = NSAlert(); alert.messageText = "Renommer la collection"; let field = NSTextField(string: board.name); field.frame = NSRect(x: 0, y: 0, width: 260, height: 26); alert.accessoryView = field; alert.addButton(withTitle: "Renommer"); alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn { history.renameBoard(board.id, name: field.stringValue) }
    }
    private func confirmDelete(_ board: Pinboard) {
        let alert = NSAlert(); alert.messageText = "Supprimer « \(board.name) » ?"; alert.informativeText = "Ses éléments restent dans l’historique. La durée de conservation s’appliquera à nouveau aux éléments sans collection ni favori."; alert.addButton(withTitle: "Supprimer"); alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn { history.deleteBoard(board) }
    }
    private func confirmEmpty() { let alert = NSAlert(); alert.messageText = "Vider définitivement la corbeille ?"; alert.addButton(withTitle: "Vider"); alert.addButton(withTitle: "Annuler"); if alert.runModal() == .alertFirstButtonReturn { history.emptyTrash() } }
}

struct SearchBar: View {
    @ObservedObject var history: History
    @FocusState private var focused: Bool
    var focusOnAppear = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Rechercher un texte, une image, une idée…", text: $history.query).textFieldStyle(.plain).focused($focused).font(.system(size: 13))
            if !history.query.isEmpty { Button { history.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain) }
            KeyCap(text: "⌘F")
        }.padding(.horizontal, 14).padding(.vertical, 10).background(Theme.raised.opacity(0.75), in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.05)))
        .onAppear { if focusOnAppear { focused = true } }
        .onReceive(NotificationCenter.default.publisher(for: .init("EasyPaste.focusSearch"))) { _ in focused = true }
    }
}
struct FilterBar: View {
    @ObservedObject var history: History
    var body: some View {
        HStack(spacing: 5) {
            pill("Tout", selected: history.filter == nil) { history.filter = nil }
            ForEach(ClipKind.allCases, id: \.self) { kind in pill(kind.label, selected: history.filter == kind) { history.filter = kind } }
            Spacer(minLength: 4)
            Menu { Button("Toutes les applications") { history.sourceFilter = "" }; ForEach(history.sources, id: \.self) { source in Button(source) { history.sourceFilter = source } } } label: { Label(history.sourceFilter.isEmpty ? "Application" : history.sourceFilter, systemImage: "line.3.horizontal.decrease").lineLimit(1) }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
            Toggle("Aujourd’hui", isOn: $history.todayOnly).toggleStyle(.button).font(.system(size: 10)).tint(Theme.mint)
        }
    }
}
func pill(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(text).font(.system(size: 11, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? Theme.mint : Theme.muted).padding(.horizontal, 11).padding(.vertical, 7).background(selected ? Theme.mint.opacity(0.1) : .clear, in: Capsule()) }.buttonStyle(.plain)
}
func eyebrow(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted) }

struct ClipGrid: View {
    @ObservedObject var history: History
    @State private var limit = 80
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 215, maximum: 340), spacing: 15)], spacing: 15) {
                ForEach(history.visible.prefix(limit)) { clip in ClipCard(history: history, clip: clip, compact: history.compact) }
            }.padding(3)
            if history.visible.count > limit { Button("Afficher la suite (\(history.visible.count - limit))") { limit += 80 }.buttonStyle(PasteButtonStyle()).padding(18) }
        }.onChange(of: history.collection) { _, _ in limit = 80 }.onChange(of: history.query) { _, _ in limit = 80 }
    }
}
struct ClipCard: View {
    @ObservedObject var history: History
    let clip: Clip
    let compact: Bool
    var quickIndex: Int? = nil
    @State private var hovered = false
    private var selected: Bool { history.selected == clip.id || history.selectedIDs.contains(clip.id) }
    private var accent: Color { clip.kind.accent }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: clip.kind.symbol).foregroundStyle(accent).font(.system(size: 11, weight: .medium)).frame(width: 25, height: 25).background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                Text(clip.source).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(Theme.muted)
                Spacer(minLength: 3)
                if clip.kind == .image, clip.trashedAt == nil {
                    Button { history.annotate?(clip) } label: { Image(systemName: "pencil.tip.crop.circle").font(.system(size: 15)).foregroundStyle(Theme.mint) }.buttonStyle(.plain).opacity(hovered || selected ? 1 : 0).help("Annoter · ⌘E").accessibilityLabel("Annoter l’image").disabled(history.annotating || history.captureBusy)
                }
                if clip.pinned { Image(systemName: "star.fill").foregroundStyle(Theme.mint).font(.system(size: 9)) }
                Menu { ClipActions(history: history, clip: clip) } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.muted).frame(width: 18, height: 18) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Actions de l’élément")
            }.padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 13)
            ClipContent(clip: clip, compact: compact).overlay {
                if clip.kind == .video { Button { history.previewing = clip } label: { Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(.white).padding(16).background(.black.opacity(0.6), in: Circle()) }.buttonStyle(.plain).help("Lire la vidéo") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.horizontal, 15).clipped()
            HStack {
                Text(clip.kind == .video ? "VIDÉO · " + clip.durationLabel : clip.parentID != nil ? "MODIFIÉE" : history.originalIDs.contains(clip.id) ? "ORIGINAL" : clip.kind == .image ? (history.ocrTasks.contains(clip.id) ? "LECTURE DU TEXTE…" : clip.ocr.isEmpty ? "IMAGE" : "IMAGE · TEXTE DÉTECTÉ") : clip.kind == .file ? "FICHIER" : clip.kind == .link ? "LIEN" : clip.kind == .color ? "COULEUR" : "\(clip.text.count) CARACTÈRES").font(.system(size: 8, weight: .medium)).tracking(0.5)
                Spacer()
                if let i = quickIndex, i < 9 { Text("⌘\(i+1)").font(.system(size: 9, design: .monospaced)) }
                else { Text(ClipDate.label(clip.date)).font(.system(size: 9)).lineLimit(1) }
            }.foregroundStyle(Theme.muted).padding(14)
        }
        .frame(height: compact ? 145 : 230)
        .background(LinearGradient(colors: [accent.opacity(hovered ? 0.14 : 0.085), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(selected ? Theme.mint.opacity(0.9) : .white.opacity(hovered ? 0.19 : 0.09), lineWidth: selected ? 1.5 : 1))
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .onTapGesture(count: 2) { if clip.trashedAt != nil { history.restore(clip) } else { history.paste?([clip], false) } }
        .onTapGesture { history.select(clip, modifiers: NSEvent.modifierFlags); NSApp.keyWindow?.makeFirstResponder(nil) }
        .onHover { hovered = $0 }
        .contextMenu { ClipActions(history: history, clip: clip) }
        .onDrag { DragProvider.make(clip, history: history) }
        .accessibilityElement(children: .contain).accessibilityLabel("\(clip.title), \(clip.kind.label), \(clip.source)")
        .accessibilityAction { history.select(clip); NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}
struct ClipContent: View {
    @Environment(\.displayScale) private var displayScale
    let clip: Clip
    var compact = false
    var body: some View {
        Group {
            if clip.kind == .image || clip.kind == .video {
                if let image = clip.image { GeometryReader { geo in Image(nsImage: image).resizable().scaledToFit().frame(width: min(geo.size.width, image.size.width / displayScale), height: min(geo.size.height, image.size.height / displayScale)).frame(width: geo.size.width, height: geo.size.height) }.clipShape(RoundedRectangle(cornerRadius: 10)) }
                else { Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if clip.kind == .color {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 11).fill(colorFromHex(clip.text))
                    VStack(alignment: .leading, spacing: 4) { Text(clip.text.uppercased()).font(.system(size: compact ? 16 : 22, weight: .medium, design: .monospaced)); if !compact { Text("La nuance qu’il te fallait.").font(.system(size: 11)) } }.foregroundStyle(.black).padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9)).padding(9)
                }

            } else if clip.kind == .link {
                VStack(alignment: .leading, spacing: 12) { Image(systemName: "arrow.up.right").font(.system(size: compact ? 17 : 25, weight: .light)).foregroundStyle(Theme.mint); Text(URL(string: clip.text)?.host ?? clip.title).font(.system(size: 17, weight: .semibold)).lineLimit(2); if !compact { Text(String(clip.text.prefix(160))).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(3) } }
            } else if clip.kind == .file {
                VStack(alignment: .leading, spacing: 10) { Image(systemName: "doc.text").font(.system(size: compact ? 22 : 35, weight: .light)).foregroundStyle(Theme.colors[2]); Text(clip.title).font(.system(size: 14, weight: .medium)).lineLimit(3); if !compact { Text(String(clip.text.prefix(180))).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2) } }
            } else {
                VStack(alignment: .leading, spacing: 9) { Text(clip.title).font(.system(size: compact ? 13 : 16, weight: .semibold)).tracking(-0.25).lineLimit(compact ? 2 : 2); if !compact { Text(String(clip.text.prefix(700))).font(.system(size: 12.5)).lineSpacing(4).foregroundStyle(Theme.ink.opacity(0.72)).lineLimit(5) } }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
func colorFromHex(_ value: String) -> Color {
    var s = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
    if s.count == 8 { s = String(s.prefix(6)) }
    guard let n = UInt64(s, radix: 16) else { return Theme.mint }
    return Color(red: Double((n >> 16) & 255)/255, green: Double((n >> 8) & 255)/255, blue: Double(n & 255)/255)
}
struct ClipActions: View {
    @ObservedObject var history: History
    let clip: Clip
    var body: some View {
        if clip.trashedAt != nil { Button("Restaurer") { history.restore(clip) }; Button("Supprimer définitivement…", role: .destructive) { confirmPermanentDeletion(history, items: [clip]) } }
        else {
            Button("Coller") { history.paste?([clip], false) }
            Button("Copier") { Task { _ = await history.copy([clip]) } }
            Button(clip.kind == .image ? "Copier le texte détecté" : "Copier en texte brut") { Task { _ = await history.copy([clip], plain: true) } }.disabled((clip.kind == .image && clip.ocr.isEmpty) || clip.kind == .video)
            Divider()
            Button("Aperçu") { history.previewing = clip }
            if clip.kind == .image { Button("Annoter une copie…") { history.annotate?(clip) }.disabled(history.annotating || history.captureBusy) }
            if clip.kind == .video { Button("Enregistrer la vidéo…") { history.exportVideo(clip) } }
            if clip.editable { Button("Modifier…") { history.editing = clip } }
            if clip.kind == .link || clip.kind == .file { Button("Ouvrir dans l’application par défaut") { openClip(clip) } }
            Button(clip.pinned ? "Retirer des favoris" : "Garder en favori") { history.togglePin(clip) }
            Menu("Collections") { ForEach(history.boards) { board in Button((clip.boards.contains(board.id) ? "✓ " : "") + board.name) { history.toggleBoard(clip, board) } }; Divider(); Button("Nouvelle collection…") { history.showNewBoard = true } }
            Button("Ajouter à la pile") { history.queue(clip) }
            Divider()
            Button("Mettre à la corbeille", role: .destructive) { history.trash(clip) }
        }
    }
}
func openClip(_ clip: Clip) {
    if clip.kind == .link, let url = URL(string: clip.text), ["http","https","mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
    if clip.kind == .file { for line in clip.text.split(separator: "\n") { NSWorkspace.shared.open(URL(fileURLWithPath: String(line))) } }
}
struct EmptyState: View {
    @ObservedObject var history: History
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 17).fill(Theme.colors[1].opacity(0.10)).frame(width: 150, height: 118).rotationEffect(.degrees(-13)).offset(x: -27, y: 7)
                RoundedRectangle(cornerRadius: 17).fill(Theme.mint.opacity(0.10)).frame(width: 150, height: 118).rotationEffect(.degrees(10)).offset(x: 25, y: 6)
                VStack(alignment: .leading, spacing: 13) { Image(systemName: "text.quote").font(.system(size: 24)).foregroundStyle(Theme.mint); Capsule().fill(Theme.muted.opacity(0.25)).frame(width: 85, height: 4); Capsule().fill(Theme.muted.opacity(0.15)).frame(width: 60, height: 4) }.frame(width: 145, height: 118).background(Theme.panel, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.mint.opacity(0.2)))
            }.scaleEffect(0.78).frame(height: 94).padding(.bottom, 4)
            Text(history.fault ? "L’historique est en pause." : history.total == 0 && history.collection == "all" ? "Une copie. Mille possibilités." : "Une place pour la suite.").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(history.fault ? history.notice : history.total == 0 && history.collection == "all" ? "Copie du texte, une image ou un lien.\nEasyPaste les garde ici, pour quand tu en auras besoin." : "Aucun élément ne correspond à cette vue.\nAjoute une copie ou ajuste tes filtres.").font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            if !history.enabled && !history.fault { Button("Activer mon historique") { history.enabled = true; history.report("Historique activé. Copie un élément dans une autre application.") }.buttonStyle(PasteButtonStyle(primary: true)) }
            HStack(spacing: 18) { Label("Sur ton Mac", systemImage: "internaldrive"); Label("Chiffré", systemImage: "lock"); Label("Gratuit · MIT", systemImage: "heart") }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.top, 6)
        }.padding(20)
    }
}

struct ShelfView: View {
    @ObservedObject var history: History
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 17) {
                Button { history.showLibrary?() } label: { BrandMark(size: 28) }.buttonStyle(.plain).help("Ouvrir la bibliothèque")
                SearchBar(history: history, focusOnAppear: true).frame(maxWidth: 440)
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 2) {
                    pill("Historique", selected: history.collection == "all") { history.collection = "all" }
                    pill("Favoris", selected: history.collection == "pinned") { history.collection = "pinned" }
                    ForEach(history.boards) { board in pill(board.name, selected: history.collection == board.id.uuidString) { history.collection = board.id.uuidString } }
                    pill("Pile (\(history.stack.count))", selected: history.collection == "stack") { history.collection = "stack" }
                } }
                CaptureMenu(history: history)
                Button { history.compact.toggle() } label: { Image(systemName: history.compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }.buttonStyle(.plain).help(history.compact ? "Agrandir les cartes" : "Mode compact")
                Button { history.closeShelf?() } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain).help("Fermer · Échap")
            }
            if history.loading { ProgressView("Ouverture…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if history.visible.isEmpty {
                VStack(spacing: 10) { Text(history.enabled ? "Ta prochaine copie t’attend ici." : "Active l’historique pour retrouver tes copies.").font(.system(size: 17, weight: .medium)); Button("Ouvrir la bibliothèque") { history.showLibrary?() }.buttonStyle(PasteButtonStyle(primary: true)) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 13) { ForEach(Array(history.visible.enumerated()), id: \.element.id) { index, clip in ClipCard(history: history, clip: clip, compact: history.compact, quickIndex: index).frame(width: history.compact ? 215 : 236).id(clip.id) } }.padding(3)
                    }.onChange(of: history.selected) { _, value in if let value { proxy.scrollTo(value) } }
                }
            }
            HStack(spacing: 14) {
                Label("Entrée pour coller", systemImage: "return"); Text("⇧Entrée · texte brut"); Text("⌘1–9 · collage rapide")
                Spacer()
                if !history.recentlyTrashed.isEmpty { Button("Annuler la suppression") { history.undoTrash() }.buttonStyle(.plain).foregroundStyle(Theme.mint) }
                if !history.selection.isEmpty { Button { history.trashItems(history.selection) } label: { Label("Supprimer\(history.selection.count > 1 ? " (\(history.selection.count))" : "")", systemImage: "trash") }.buttonStyle(.plain).help("Supprimer la sélection") }
                Text("\(history.visible.count) élément(s)")
                Text(history.enabled ? "Collecte active" : "En pause").foregroundStyle(history.enabled ? Theme.mint : Theme.muted)
            }.font(.system(size: 10)).foregroundStyle(Theme.muted)
        }.overlay(alignment: .bottomLeading) {
            if let toast = history.toast { Text(toast).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.mint).lineLimit(2).padding(.horizontal, 13).padding(.vertical, 9).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.mint.opacity(0.25))).padding(.bottom, 29).allowsHitTesting(false) }
        }.padding(20).background(LinearGradient(colors: [Theme.raised, Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 23)).overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.14))).foregroundStyle(Theme.ink).preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "fr_FR")).modifier(HistorySheets(history: history, host: "shelf"))
    }
}
@MainActor enum DragProvider {
    static func make(_ clip: Clip, history: History) -> NSItemProvider {
        if clip.kind == .file, let first = clip.text.split(separator: "\n").first { return NSItemProvider(object: URL(fileURLWithPath: String(first)) as NSURL) }
        let provider = NSItemProvider()
        if clip.kind == .video {
            provider.registerFileRepresentation(forTypeIdentifier: UTType.mpeg4Movie.identifier, fileOptions: [], visibility: .all) { completion in
                Task { @MainActor in do { completion(try await history.videoURL(clip), false, nil) } catch { completion(nil, false, error) } }
                return nil
            }
            provider.suggestedName = "EasyPaste.mp4"; return provider
        }
        let type = clip.kind == .image ? UTType.png.identifier : UTType.utf8PlainText.identifier
        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
            Task { @MainActor in
                do {
                    let full = try await history.fullClip(clip)
                    let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                        if clip.kind != .image { return Data(full.text.utf8) }
                        if let png = full.payload.representations.flatMap({ $0 }).first(where: { $0.type == NSPasteboard.PasteboardType.png.rawValue })?.data { return png }
                        guard let raw = full.imageData, let bitmap = NSBitmapImageRep(data: raw) else { return nil }
                        return bitmap.representation(using: .png, properties: [:])
                    }.value
                    completion(data, data == nil ? CocoaError(.fileReadCorruptFile) : nil)
                } catch { completion(nil, error) }
            }
            return nil
        }
        if clip.editable {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                Task { @MainActor in
                    do { let full = try await history.fullClip(clip); let rtf = full.payload.representations.flatMap { $0 }.first { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }?.data ?? NSAttributedString(string: full.text).rtf(from: NSRange(location: 0, length: (full.text as NSString).length), documentAttributes: [:]); completion(rtf, nil) } catch { completion(nil, error) }
                }; return nil
            }
        }
        provider.suggestedName = clip.title
        return provider
    }
}

private enum ClipDate {
    static func label(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "à l’instant" }
        if seconds < 3600 { return "il y a \(seconds / 60) min" }
        if seconds < 86400 { return "il y a \(seconds / 3600) h" }
        return "il y a \(seconds / 86400) j"
    }
}
extension ClipKind {
    var accent: Color { switch self { case .text: Theme.colors[1]; case .link: Theme.mint; case .image: Theme.colors[3]; case .file: Theme.colors[2]; case .color: Theme.mint; case .video: Theme.colors[1] } }
}

@MainActor func confirmPermanentDeletion(_ history: History, items: [Clip]) {
    guard !items.isEmpty else { return }
    let alert = NSAlert()
    alert.messageText = items.count == 1 ? "Supprimer définitivement cet élément ?" : "Supprimer définitivement ces \(items.count) éléments ?"
    alert.informativeText = "Cette action retire les copies de l’historique EasyPaste et ne peut pas être annulée. Les fichiers d’origine ne sont pas supprimés."
    alert.addButton(withTitle: "Supprimer définitivement"); alert.addButton(withTitle: "Annuler")
    if alert.runModal() == .alertFirstButtonReturn { history.permanentlyDelete(items) }
}

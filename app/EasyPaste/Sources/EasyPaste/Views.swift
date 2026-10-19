import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SearchBar: View {
    @ObservedObject var history: History
    @FocusState private var focused: Bool
    var focusOnAppear = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Rechercher dans l’historique…", text: $history.query).textFieldStyle(.plain).focused($focused).font(.system(size: 13)).accessibilityLabel("Rechercher dans l’historique")
            if !history.query.isEmpty { Button { history.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted).frame(width: 24, height: 24) }.buttonStyle(FullAreaButtonStyle()) }
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
            Menu { Button("Toutes les applications") { history.sourceFilter = "" }; ForEach(history.sources, id: \.self) { source in Button(source) { history.sourceFilter = source } } } label: { Label(history.sourceFilter.isEmpty ? "Application" : history.sourceFilter, systemImage: "line.3.horizontal.decrease").lineLimit(1).contentShape(.interaction, Rectangle()) }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
            Toggle("Aujourd’hui", isOn: $history.todayOnly).toggleStyle(.button).font(.system(size: 10)).tint(Theme.mint)
        }
    }
}
func pill(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(text).font(.system(size: 11, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? Theme.mint : Theme.muted).padding(.horizontal, 11).padding(.vertical, 7).background(selected ? Theme.mint.opacity(0.1) : .clear, in: Capsule()) }.buttonStyle(FullAreaButtonStyle())
}
func eyebrow(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted) }

struct ClipGrid: View {
    @ObservedObject var history: History
    var listLayout = false
    @State private var limit = 80
    var body: some View {
        ScrollView {
            if listLayout {
                LazyVStack(spacing: 10) {
                    ForEach(history.visible.prefix(limit)) { clip in LibraryClipCard(history: history, clip: clip, list: true) }
                }.padding(3)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 420), spacing: 14)], spacing: 14) {
                    ForEach(history.visible.prefix(limit)) { clip in LibraryClipCard(history: history, clip: clip) }
                }.padding(3)
            }
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
                    Button { history.annotate?(clip) } label: { Image(systemName: "pencil.tip.crop.circle").font(.system(size: 15)).foregroundStyle(Theme.mint).frame(width: 24, height: 24) }.buttonStyle(FullAreaButtonStyle()).opacity(hovered || selected ? 1 : 0).help("Annoter · ⌘E").accessibilityLabel("Annoter l’image").disabled(history.annotating || history.captureBusy)
                }
                if clip.pinned { Image(systemName: "star.fill").foregroundStyle(Theme.mint).font(.system(size: 9)) }
                Menu { ClipActions(history: history, clip: clip) } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.muted).frame(width: 24, height: 24).contentShape(.interaction, Rectangle()) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Actions de l’élément")
            }.padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 13)
            ClipContent(clip: clip, compact: compact).overlay {
                if clip.kind == .video { Button { history.previewing = clip } label: { Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(.white).padding(16).background(.black.opacity(0.6), in: Circle()) }.buttonStyle(FullAreaButtonStyle()).help("Lire la vidéo") }
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
                    VStack(alignment: .leading, spacing: 4) { Text(clip.text.uppercased()).font(.system(size: compact ? 16 : 22, weight: .medium, design: .monospaced)) }.foregroundStyle(.black).padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9)).padding(9)
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
            if clip.kind == .image { Button("Annoter l’image…") { history.annotate?(clip) }.disabled(history.annotating || history.captureBusy) }
            if clip.kind == .video { Button("Enregistrer la vidéo…") { history.exportVideo(clip) } }
            if clip.editable { Button("Modifier…") { history.editing = clip } }
            if clip.kind == .link || clip.kind == .file { Button("Ouvrir") { openClip(clip) } }
            Button(clip.pinned ? "Retirer des favoris" : "Ajouter aux favoris") { history.togglePin(clip) }
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
            Text(history.fault ? "L’historique est en pause." : history.total == 0 && history.collection == "all" ? "Historique vide" : "Aucun élément").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(history.fault ? history.notice : history.total == 0 && history.collection == "all" ? "Copie du texte, une image ou un lien pour commencer." : "Modifie les filtres ou ajoute un élément.").font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            if !history.enabled && !history.fault { Button("Activer l’historique") { history.enabled = true; history.report("Historique activé. Copie un élément dans une autre application.") }.buttonStyle(PasteButtonStyle(primary: true)) }
        }.padding(20)
    }
}

struct ShelfView: View {
    @ObservedObject var history: History
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 17) {
                Button { history.showLibrary?() } label: { BrandMark(size: 28) }.buttonStyle(FullAreaButtonStyle()).help("Ouvrir la bibliothèque")
                SearchBar(history: history, focusOnAppear: true).frame(maxWidth: 440)
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 2) {
                    pill("Historique", selected: history.collection == "all") { history.collection = "all" }
                    pill("Favoris", selected: history.collection == "pinned") { history.collection = "pinned" }
                    ForEach(history.boards) { board in pill(board.name, selected: history.collection == board.id.uuidString) { history.collection = board.id.uuidString } }
                    pill("Pile (\(history.stack.count))", selected: history.collection == "stack") { history.collection = "stack" }
                } }
                CaptureMenu(history: history)
                Button { history.compact.toggle() } label: { Image(systemName: history.compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }.buttonStyle(FullAreaButtonStyle(minimumSize: 24)).help(history.compact ? "Agrandir les cartes" : "Mode compact")
                Button { history.closeShelf?() } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(FullAreaButtonStyle(minimumSize: 24)).help("Fermer · Échap")
            }
            if history.loading { ProgressView("Ouverture…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if history.visible.isEmpty {
                VStack(spacing: 10) { Text(history.enabled ? "Aucun élément" : "Historique en pause").font(.system(size: 17, weight: .medium)); Button("Ouvrir la bibliothèque") { history.showLibrary?() }.buttonStyle(PasteButtonStyle(primary: true)) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 13) { ForEach(Array(history.visible.enumerated()), id: \.element.id) { index, clip in ClipCard(history: history, clip: clip, compact: history.compact, quickIndex: index).frame(width: history.compact ? 215 : 236).id(clip.id) } }.padding(3)
                    }.onChange(of: history.selected) { _, value in if let value { proxy.scrollTo(value) } }
                }
            }
            HStack(spacing: 14) {
                Label("Coller", systemImage: "return"); Text("⇧Entrée · texte brut"); Text("⌘1–9 · collage rapide")
                Spacer()
                if !history.recentlyTrashed.isEmpty { Button("Annuler la suppression") { history.undoTrash() }.buttonStyle(FullAreaButtonStyle()).foregroundStyle(Theme.mint) }
                if !history.selection.isEmpty { Button { history.trashItems(history.selection) } label: { Label("Supprimer\(history.selection.count > 1 ? " (\(history.selection.count))" : "")", systemImage: "trash") }.buttonStyle(FullAreaButtonStyle()).help("Supprimer la sélection") }
                Text("\(history.visible.count) élément\(history.visible.count == 1 ? "" : "s")")
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

enum ClipDate {
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

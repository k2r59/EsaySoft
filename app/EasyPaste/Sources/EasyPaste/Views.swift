import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SearchBar: View {
    @ThemePalette private var palette
    @ObservedObject var history: History
    @State private var focused = false
    @Environment(\.colorSchemeContrast) private var contrast
    var focusOnAppear = false
    var glass = false
    var integrated = false
    @AppStorage(GlassAppearance.key) private var transparency = GlassAppearance.defaultTransparency
    private var secondary: Color { integrated ? Theme.chromeSecondary : Theme.muted }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(secondary)
            SearchInput(text: $history.query, focused: $focused,
                        prompt: glass ? "Rechercher…" : "Rechercher dans l’historique…",
                        color: secondary, fontSize: glass ? 15 : 13, focusOnAppear: focusOnAppear)
            if !history.query.isEmpty { Button { history.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(secondary).frame(width: 24, height: 24) }.buttonStyle(FullAreaButtonStyle()) }
            if !glass { KeyCap(text: "⌘F") }
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .background {
                if integrated {
                    RoundedRectangle(cornerRadius: 14).fill(palette.controlPlate.opacity(0.48 - 0.3 * GlassAppearance.transparency(transparency)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
                } else {
                    RoundedRectangle(cornerRadius: glass ? 20 : 14).fill(palette.controlPlate.opacity(0.96)).glassControlFinish(radius: glass ? 20 : 14)
                }
            }
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: glass ? 20 : 14).strokeBorder(Theme.ink.opacity(0.6), lineWidth: 1.5)
                } else if !integrated {
                    RoundedRectangle(cornerRadius: glass ? 20 : 14).strokeBorder(focused ? palette.accent.opacity(0.65) : palette.accent.opacity(0.12), lineWidth: focused ? 1.5 : 0.75)
                }
            }
            .overlay(alignment: .bottom) {
                if integrated && focused {
                    Capsule().fill(palette.chromeAccent.opacity(0.35)).frame(height: 1).padding(.horizontal, 16).allowsHitTesting(false)
                }
            }
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
    @ThemePalette private var palette
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
                SourceApplicationIcon(clip: clip)
                Text(clip.shelfTypeLabel).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(Theme.ink).help("Copié depuis \(clip.source)")
                Spacer(minLength: 3)
                if history.showPasteCounts { PasteCountBadge(count: history.pasteUsage.count(for: clip.id)) }
                if !compact { Text(ClipDate.label(clip.date)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1) }
            }.padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 13)
            ClipContent(clip: clip, compact: compact).overlay {
                if clip.kind == .video { Button { history.openPreview(clip) } label: { Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(.white).padding(16).background(.black.opacity(0.6), in: Circle()) }.buttonStyle(FullAreaButtonStyle()).help("Lire la vidéo") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.horizontal, 15).clipped()
            ClipCardFooter(history: history, clip: clip, quickIndex: quickIndex)
                .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .frame(height: compact ? 145 : 215)
        .background {
            RoundedRectangle(cornerRadius: 17).fill(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [accent.opacity(hovered ? 0.10 : 0.065), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(selected ? palette.accent : (hovered ? Theme.hoverBorder : Theme.border), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .modifier(CardInteraction(history: history, clip: clip))
        .onHover { hovered = $0 }
        .contextMenu { ClipActions(history: history, clip: clip) }
        .onDrag { DragProvider.make(clip, history: history) }
        .accessibilityElement(children: .contain).accessibilityLabel("\(clip.title), \(clip.kind.label), \(clip.source)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Double-clique pour coller. Espace pour l’aperçu.")
        .accessibilityAction { CardInteraction(history: history, clip: clip).select(clickCount: 1, modifiers: []) }
        .accessibilityAction(named: Text("Coller")) { CardInteraction(history: history, clip: clip).activate(modifiers: []) }
    }
}
struct ClipContent: View {
    @Environment(\.displayScale) private var displayScale
    let clip: Clip
    var compact = false
    var showsImageMetadata = true
    var body: some View {
        Group {
            if clip.kind == .image || clip.kind == .video {
                if let image = clip.image { GeometryReader { geo in Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(width: min(geo.size.width, image.size.width / displayScale), height: min(geo.size.height, image.size.height / displayScale)).frame(width: geo.size.width, height: geo.size.height) }.clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottomTrailing) {
                            if showsImageMetadata, let metadata = clip.imageMetadata {
                                Text(metadata.dimensions).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 7).padding(.vertical, 4).background(Theme.panel.opacity(0.96), in: Capsule()).padding(5)
                                    .help("\(metadata.dimensions) · \(metadata.fileSize)").allowsHitTesting(false)
                            }
                        }
                }
                else { Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if clip.kind == .color {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 11).fill(colorFromHex(clip.text))
                    VStack(alignment: .leading, spacing: 4) { Text(clip.text.uppercased()).font(.system(size: compact ? 16 : 22, weight: .medium, design: .monospaced)) }.foregroundStyle(.black).padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9)).padding(9)
                }

            } else if clip.kind == .link {
                VStack(alignment: .leading, spacing: 9) {
                    Text(clip.cardTitle ?? URL(string: clip.text)?.host ?? clip.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    if !compact { Text(String(clip.text.prefix(160))).font(.system(size: 15)).foregroundStyle(Theme.adaptive("link", light: 0x0068C6, dark: 0x87C4FF)).lineLimit(3) }
                }
            } else if clip.kind == .file {
                VStack(alignment: .leading, spacing: 10) { Image(systemName: "doc.text").font(.system(size: compact ? 22 : 35, weight: .light)).foregroundStyle(Theme.colors[2]); Text(clip.title).font(.system(size: 14, weight: .medium)).lineLimit(3); if !compact { Text(String(clip.text.prefix(180))).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2) } }
            } else if let format = clip.structuredFormat {
                VStack(alignment: .leading, spacing: 7) {
                    if let title = clip.cardTitle { Text(title).font(.system(size: compact ? 13 : 15, weight: .semibold)).lineLimit(1) }
                    StructuredCardPreview(clip: clip, format: format, compact: compact)
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    if let title = clip.cardTitle, !clip.text.isEmpty { Text(title).font(.system(size: compact ? 13 : 15, weight: .semibold)).lineLimit(1) }
                    Text(String((clip.text.isEmpty ? clip.title : clip.text).prefix(700))).font(.system(size: compact ? 13 : 15)).lineSpacing(4).lineLimit(compact ? 3 : 5).frame(maxWidth: .infinity, alignment: .leading)
                }
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
            if [.text, .link, .color].contains(clip.kind) {
                Button("Coller sans mise en forme") { history.paste?([clip], true) }
                    .help("Colle le texte et les valeurs affichées, sans HTML ni mise en forme · ⇧↩")
            }
            Button("Copier") { Task { _ = await history.copy([clip]) } }
            Button(clip.kind == .image ? "Copier le texte détecté" : "Copier en texte brut") { Task { _ = await history.copy([clip], plain: true) } }.disabled((clip.kind == .image && clip.ocr.isEmpty) || clip.kind == .video)
            Divider()
            if clip.hasPreview { Button("Aperçu") { history.openPreview(clip) } }
            if clip.kind == .image { Button("Annoter l’image…") { history.annotate?(clip) }.disabled(history.annotating || history.captureBusy) }
            if clip.kind == .video { Button("Enregistrer la vidéo…") { history.exportVideo(clip) } }
            if clip.editable { Button("Modifier…") { history.editing = clip } }
            if clip.kind == .text { Button("Formater…") { history.openFormatter(clip) } }
            if clip.kind == .link || clip.kind == .file { Button("Ouvrir") { openClip(clip) } }
            Button(clip.pinned ? "Retirer des favoris" : "Ajouter aux favoris") { history.togglePin(clip) }
            Menu("Collections") { ForEach(history.boards) { board in Button((clip.boards.contains(board.id) ? "✓ " : "") + board.name) { history.toggleBoard(clip, board) } }; Divider(); Button("Nouvelle collection…") { history.showNewBoard = true } }
            Button("Ajouter à la pile") { history.queue(clip) }
            BitwardenClipMenu(model: history.bitwarden, clip: clip)
            Divider()
            Button("Mettre à la corbeille", role: .destructive) { history.requestTrash([clip]) }
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
        }.padding(20).glassLabelPlate()
    }
}

struct ShelfView: View {
    @ThemePalette private var palette
    @ObservedObject var history: History
    var nativeGlassHosted = false
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                Button { history.showLibrary?() } label: { ShelfBrandMark().frame(width: 42, height: 42).contentShape(Rectangle()) }.buttonStyle(FullAreaButtonStyle()).help("Ouvrir la bibliothèque").accessibilityLabel("Ouvrir la bibliothèque EasyPaste")
                SearchBar(history: history, focusOnAppear: true, glass: true).frame(minWidth: 180, maxWidth: 275)
                Spacer(minLength: 10).frame(maxWidth: 45)
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) {
                    shelfTab("Historique", icon: "clock", selected: history.collection == "all") { history.collection = "all" }
                    shelfTab("Favoris", icon: "star", selected: history.collection == "pinned") { history.collection = "pinned" }
                    Menu {
                        ForEach(history.boards) { board in Button(board.name) { history.collection = board.id.uuidString } }
                        if !history.boards.isEmpty { Divider() }
                        Button("Nouvelle collection…") { history.showNewBoard = true }
                    } label: { ShelfTabLabel(title: history.boards.first { $0.id.uuidString == history.collection }?.name ?? "Collections", icon: "folder", selected: history.boards.contains { $0.id.uuidString == history.collection }) }.menuStyle(.borderlessButton).fixedSize().tint(history.boards.contains { $0.id.uuidString == history.collection } ? Theme.onAccent : Theme.ink)
                    if !history.stack.isEmpty { shelfTab("Pile (\(history.stack.count))", icon: "square.stack", selected: history.collection == "stack") { history.collection = "stack" } }
                } }
                CaptureMenu(history: history, iconOnly: true)
                Button { history.page = "settings"; history.showLibrary?() } label: { Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 42, height: 42).background(palette.controlPlate.opacity(0.95), in: Circle()) }.buttonStyle(FullAreaButtonStyle()).help("Réglages").accessibilityLabel("Réglages")
            }
            if history.loading { ProgressView("Ouverture…").padding(12).glassLabelPlate().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if history.visible.isEmpty {
                VStack(spacing: 10) { Text(history.enabled ? "Aucun élément" : "Historique en pause").font(.system(size: 17, weight: .medium)); Button("Ouvrir la bibliothèque") { history.showLibrary?() }.buttonStyle(PasteButtonStyle(primary: true)) }.padding(16).glassLabelPlate().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 13) { ForEach(Array(history.visible.enumerated()), id: \.element.id) { index, clip in ClipCard(history: history, clip: clip, compact: history.compact, quickIndex: index).frame(width: history.compact ? 215 : 252).id(clip.id) } }
                            .padding(3).contentShape(Rectangle())
                    }.contentShape(Rectangle())
                    .onChange(of: history.selected) { _, value in if let value { proxy.scrollTo(value) } }
                    .onAppear { if let value = history.selected { proxy.scrollTo(value) } }
                }
            }
            if !history.recentlyTrashed.isEmpty || history.selection.count > 1 || !history.enabled { HStack(spacing: 14) {
                Spacer()
                if !history.recentlyTrashed.isEmpty { Button("Annuler la suppression") { history.undoTrash() }.buttonStyle(FullAreaButtonStyle()).foregroundStyle(palette.accent) }
                if history.selection.count > 1 { Button { history.requestTrash(history.selection) } label: { Label("Supprimer (\(history.selection.count))", systemImage: "trash").foregroundStyle(Theme.danger) }.buttonStyle(FullAreaButtonStyle()).help("Supprimer la sélection") }
                if !history.enabled { Text("Collecte en pause") }
            }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(5).glassLabelPlate() }
        }.overlay(alignment: .bottomLeading) {
            if let toast = history.toast { Text(toast).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.mint).lineLimit(2).padding(.horizontal, 13).padding(.vertical, 9).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.mint.opacity(0.25))).padding(.bottom, 29).allowsHitTesting(false) }
        }.padding(.horizontal, 22).padding(.vertical, 16).background { ShelfGlass(nativeHosted: nativeGlassHosted) }.foregroundStyle(Theme.ink).tint(palette.accent).environment(\.locale, Locale(identifier: "fr_FR")).modifier(HistorySheets(history: history, host: "shelf"))
    }
    private func shelfTab(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { ShelfTabLabel(title: title, icon: icon, selected: selected) }
            .buttonStyle(FullAreaButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ShelfTabLabel: View {
    @ThemePalette private var palette
    let title: String
    let icon: String
    let selected: Bool
    var body: some View {
        Label(title, systemImage: selected ? icon + ".fill" : icon)
            .font(.system(size: 14, weight: selected ? .semibold : .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
            .background {
                Capsule().fill(selected ? AnyShapeStyle(palette.actionGradient) : AnyShapeStyle(palette.controlPlate.opacity(0.95)))
                    .glassControlFinish(radius: 20, primary: selected)
            }
            .overlay(Capsule().strokeBorder(selected ? palette.accent : Theme.border))
            .contentShape(Rectangle())
    }
}
@MainActor enum DragProvider {
    static func make(_ clip: Clip, history: History) -> NSItemProvider {
        if clip.kind == .file, let first = clip.text.split(separator: "\n").first {
            let url = URL(fileURLWithPath: String(first))
            guard SVGFile.isSVG(url.path) else { return NSItemProvider(object: url as NSURL) }
            let provider = NSItemProvider(); provider.suggestedName = url.lastPathComponent
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                Task {
                    do { _ = try await Task.detached { try SVGDocument.parse(SVGFile.read(url)) }.value; completion(Data(url.absoluteString.utf8), nil) }
                    catch { completion(nil, error) }
                }
                return nil
            }
            return provider
        }
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
                    let data = try await Task.detached(priority: .userInitiated) { () throws -> Data? in
                        if clip.kind != .image { return Data(try transferText(full).utf8) }
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
                    do {
                        let full = try await history.fullClip(clip)
                        let rtf = try await Task.detached { () throws -> Data? in
                            let text = try transferText(full)
                            if text == full.text, !isSVG(full), let existing = full.payload.representations.flatMap({ $0 }).first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue })?.data { return existing }
                            return NSAttributedString(string: text).rtf(from: NSRange(location: 0, length: (text as NSString).length), documentAttributes: [:])
                        }.value
                        completion(rtf, nil)
                    } catch { completion(nil, error) }
                }; return nil
            }
        }
        provider.suggestedName = clip.title
        return provider
    }
    nonisolated private static func isSVG(_ clip: Clip) -> Bool {
        SVGDocument.looksLikeSVG(clip.text) || clip.payload.representations.flatMap({ $0 }).contains { [SVGDocument.pasteboardType, "image/svg+xml"].contains($0.type) }
    }
    nonisolated private static func transferText(_ clip: Clip) throws -> String {
        try isSVG(clip) ? SVGDocument.parse(clip.text).canonical : clip.text
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
extension Clip {
    var shelfTypeLabel: String {
        switch kind {
        case .text: structuredFormat == nil ? "Texte" : "Code"
        case .image: source == "EasyPaste" ? "Capture d’écran" : "Image"
        case .link: "Lien"
        case .file: "Fichier"
        case .video: "Vidéo"
        case .color: "Couleur"
        }
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

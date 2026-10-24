import AppKit
import SwiftUI

struct MainView: View {
    @ThemePalette private var palette
    @ObservedObject var history: History
    @AppStorage("libraryListLayout") private var listLayout = false
    private var selection: [Clip] { history.selection }
    private var title: String {
        switch history.collection {
        case "all": "Historique"
        case "pinned": "Favoris"
        case "stack": "Pile de collage"
        case "trash": "Corbeille"
        default: history.boards.first { $0.id.uuidString == history.collection }?.name ?? "Collection"
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.padding(.horizontal, 10).padding(.vertical, 12).frame(width: 212)
            if history.page == "settings" { SettingsView(history: history) }
            else { library }
        }
        .background { AppBackdrop().ignoresSafeArea() }.foregroundStyle(Theme.ink).tint(palette.accent)
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .modifier(HistorySheets(history: history))
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) { BrandMark(size: 35); Text("EasyPaste").font(.system(size: 21, weight: .semibold)) }
                .padding(.top, 12).padding(.bottom, 8)
            VStack(spacing: 5) {
                nav("Historique", "clock", "all")
                nav("Favoris", "star", "pinned")
                nav("Pile de collage", "square.stack.3d.up", "stack", count: history.stack.count)
            }
            Rectangle().fill(palette.accent.opacity(0.12)).frame(height: 1)
            HStack {
                Text("COLLECTIONS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.chromeSecondary); Spacer()
                Button { history.showNewBoard = true } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                    .buttonStyle(FullAreaButtonStyle()).help("Créer une collection").accessibilityLabel("Créer une collection")
            }
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(history.boards) { board in
                        Button { navigate(board.id.uuidString) } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Theme.colors[board.color % 4]).frame(width: 10, height: 10)
                                Text(board.name).lineLimit(1); Spacer()
                                if history.collection == board.id.uuidString { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
                            }.padding(12).foregroundStyle(history.collection == board.id.uuidString && history.page == "library" ? Theme.onAccent : Theme.ink)
                                .background { navigationBackground(history.collection == board.id.uuidString && history.page == "library") }
                        }.buttonStyle(FullAreaButtonStyle()).contextMenu {
                            Button("Renommer…") { rename(board) }
                            Button("Supprimer la collection…") { confirmDelete(board) }
                        }
                    }
                    if history.boards.isEmpty {
                        Text("Aucune collection").font(.system(size: 12)).foregroundStyle(Theme.chromeSecondary).padding(.horizontal, 10)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 5) {
                Rectangle().fill(palette.accent.opacity(0.12)).frame(height: 1).padding(.bottom, 12)
                nav("Corbeille", "trash", "trash")
                Button { history.page = "settings" } label: {
                    Label("Réglages", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .foregroundStyle(history.page == "settings" ? Theme.onAccent : Theme.ink)
                        .background { navigationBackground(history.page == "settings") }
                }.buttonStyle(FullAreaButtonStyle())
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(history.enabled ? palette.chromeAccent : Theme.chromeSecondary).frame(width: 7, height: 7)
                    Text(history.enabled ? "Collecte active" : "Collecte en pause").font(.system(size: 12)).foregroundStyle(history.enabled ? palette.chromeAccent : Theme.chromeSecondary)
                    Spacer(minLength: 0)
                    Button { history.enabled.toggle() } label: { Image(systemName: history.enabled ? "pause.circle" : "play.circle").font(.system(size: 23)).frame(width: 28, height: 28) }
                        .buttonStyle(FullAreaButtonStyle()).disabled(history.fault || history.loading)
                        .help(history.enabled ? "Mettre la collecte en pause" : "Reprendre la collecte")
                        .accessibilityLabel(history.enabled ? "Mettre la collecte en pause" : "Reprendre la collecte")
                }
                Label("Stockage local", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(Theme.chromeSecondary)
            }
        }.padding(.horizontal, 12).padding(.bottom, 18).font(.system(size: 13))
    }
    private func nav(_ label: String, _ icon: String, _ id: String, count: Int = 0) -> some View {
        let selected = history.collection == id && history.page == "library"
        return Button { navigate(id) } label: {
            HStack(spacing: 11) {
                Image(systemName: selected ? icon + ".fill" : icon).font(.system(size: 17)).frame(width: 21)
                Text(label); Spacer(minLength: 2)
                if count > 0 { Text("\(count)").font(.system(size: 11, design: .monospaced)).padding(5).foregroundStyle(selected ? Theme.onAccent : Theme.ink).background(selected ? palette.accentEnd : palette.controlPlate, in: Capsule()) }
            }.padding(.horizontal, 12).frame(height: 43)
                .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
                .background { navigationBackground(selected) }
        }.buttonStyle(FullAreaButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private func navigationBackground(_ selected: Bool) -> some View {
        if selected { RoundedRectangle(cornerRadius: 11).fill(palette.actionGradient).glassControlFinish(radius: 11, primary: true) }
    }
    private func navigate(_ id: String) { history.page = "library"; history.collection = id; history.query = "" }
    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SearchBar(history: history, integrated: true)
                Button { history.openShelf?() } label: { HStack(spacing: 9) { Image(systemName: "rectangle.bottomthird.inset.filled"); Text("Barre rapide"); KeyCap(text: "⇧⌘V") } }
                    .buttonStyle(PasteButtonStyle()).fixedSize()
            }.padding(.top, 10)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) { heading; Spacer(minLength: 8); LibraryCaptureActions(history: history) }
                VStack(alignment: .leading, spacing: 14) { heading; LibraryCaptureActions(history: history) }
            }
            LibraryFilters(history: history, listLayout: $listLayout)
            if history.collection == "stack" { stackControls }
            HStack(spacing: 9) {
                Text(history.query.isEmpty ? "Dernières copies" : "Résultats").font(.system(size: 15, weight: .semibold))
                Text("\(history.visible.count) élément\(history.visible.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.chromeSecondary)
                Spacer()
                if history.collection == "trash", !history.visible.isEmpty { Button("Vider la corbeille…") { confirmEmpty() }.buttonStyle(FullAreaButtonStyle()) }
                else { Button { history.newSnippet = true } label: { Label("Créer un texte", systemImage: "plus") }.buttonStyle(FullAreaButtonStyle(minimumSize: 28)).help("Créer un texte réutilisable") }
            }.font(.system(size: 12)).padding(.horizontal, 3)
            if history.loading { ProgressView("Ouverture de l’historique…").padding(12).glassLabelPlate().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if history.visible.isEmpty { ScrollView { EmptyState(history: history).frame(maxWidth: .infinity) }.frame(maxHeight: .infinity) }
            else { ClipGrid(history: history, listLayout: listLayout) }
            actionBar
        }.padding(.horizontal, 24).padding(.bottom, 14)
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 27, weight: .semibold)).tracking(-0.6).lineLimit(1)
            if history.collection == "trash" {
                Text("Suppression automatique après 7 jours.").font(.system(size: 12)).foregroundStyle(Theme.chromeSecondary)
            }
        }
    }
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            if history.toast != nil || history.fault || !history.recentlyTrashed.isEmpty {
                HStack {
                    Label(history.toast ?? history.notice, systemImage: history.fault ? "exclamationmark.circle" : "checkmark.circle").lineLimit(2)
                    Spacer()
                    if !history.recentlyTrashed.isEmpty { Button("Annuler la suppression") { history.undoTrash() }.buttonStyle(FullAreaButtonStyle()) }
                }.font(.system(size: 11)).foregroundStyle(history.fault ? Theme.warning : palette.accent).padding(6).glassLabelPlate()
            }
            HStack(spacing: 10) {
                Image(systemName: selection.isEmpty ? "cursorarrow" : "checkmark.square.fill").font(.system(size: 20)).foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.isEmpty ? "Sélectionne un élément" : "\(selection.count) élément\(selection.count > 1 ? "s sélectionnés" : " sélectionné")").font(.system(size: 12, weight: .medium))
                    if selection.isEmpty { Text("Double-clic : coller · Espace : aperçu").font(.system(size: 11)).foregroundStyle(Theme.chromeSecondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if history.collection == "trash" {
                    Button("Restaurer") { selection.forEach { history.restore($0) } }.buttonStyle(PasteButtonStyle()).disabled(selection.isEmpty)
                    Button("Supprimer…") { confirmPermanentDeletion(history, items: selection) }.buttonStyle(PasteButtonStyle()).disabled(selection.isEmpty)
                } else {
                    if selection.count == 1, let clip = selection.first {
                        if clip.kind == .image { Button { history.annotate?(clip) } label: { Label("Annoter", systemImage: "pencil.tip.crop.circle") }.buttonStyle(PasteButtonStyle()).disabled(history.annotating || history.captureBusy) }
                        else if clip.structuredFormat != nil { Button { history.openFormatter(clip) } label: { Label("Formater…", systemImage: "curlybraces") }.buttonStyle(PasteButtonStyle()) }
                        else if clip.editable { Button { history.editing = clip } label: { Label("Modifier", systemImage: "pencil") }.buttonStyle(PasteButtonStyle()) }
                        else if clip.kind == .video { Button { history.openPreview(clip) } label: { Label("Lire", systemImage: "play") }.buttonStyle(PasteButtonStyle()) }
                    }
                    Menu {
                        Button("Favoris") { for clip in selection where !clip.pinned { history.mutate(clip.id) { $0.pinned = true } } }
                        ForEach(history.boards) { board in Button(board.name) { for clip in selection where !clip.boards.contains(board.id) { history.toggleBoard(clip, board) } } }
                        Divider(); Button("Nouvelle collection…") { history.showNewBoard = true }
                    } label: { Label("Ajouter à…", systemImage: "folder").contentShape(Rectangle()) }
                    .menuStyle(.button).buttonStyle(PasteButtonStyle()).fixedSize().tint(Theme.ink).disabled(selection.isEmpty)
                    Button { history.requestTrash(selection) } label: { Image(systemName: "trash").foregroundStyle(Theme.danger).frame(width: 16) }.buttonStyle(PasteButtonStyle()).help("Supprimer la sélection").accessibilityLabel("Supprimer la sélection").disabled(selection.isEmpty)
                    Button { Task { _ = await history.copy(selection) } } label: { Label("Copier", systemImage: "doc.on.doc") }.buttonStyle(PasteButtonStyle(primary: true)).disabled(selection.isEmpty)
                }
            }.padding(.horizontal, 3).frame(minHeight: 62)
        }
    }
    private var stackControls: some View {
        HStack(spacing: 10) {
            Toggle("Collecter dans la pile", isOn: $history.stackRecording).toggleStyle(.switch).controlSize(.small)
            Spacer()
            Button("Inverser") { history.stack.reverse() }.buttonStyle(PasteButtonStyle())
            Button("Copier le suivant") { Task { if let id = history.stack.first, let c = history.clips.first(where: { $0.id == id }), await history.copy([c]) { history.consumeStack([c]) } } }.buttonStyle(PasteButtonStyle(primary: true)).disabled(history.stack.isEmpty)
        }.font(.system(size: 12)).padding(12).surface()
    }
    private func rename(_ board: Pinboard) {
        let alert = NSAlert(); alert.messageText = "Renommer la collection"
        let field = NSTextField(string: board.name); field.frame = NSRect(x: 0, y: 0, width: 260, height: 26); alert.accessoryView = field
        alert.addButton(withTitle: "Renommer"); alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn { history.renameBoard(board.id, name: field.stringValue) }
    }
    private func confirmDelete(_ board: Pinboard) {
        let alert = NSAlert(); alert.messageText = "Supprimer « \(board.name) » ?"; alert.informativeText = "Ses éléments restent dans l’historique. La durée de conservation s’appliquera à nouveau aux éléments sans collection ni favori."
        alert.addButton(withTitle: "Supprimer"); alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn { history.deleteBoard(board) }
    }
    private func confirmEmpty() {
        let alert = NSAlert(); alert.messageText = "Vider définitivement la corbeille ?"; alert.addButton(withTitle: "Vider"); alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn { history.emptyTrash() }
    }
}

struct LibraryCaptureActions: View {
    @ThemePalette private var palette
    @ObservedObject var history: History
    private var unavailable: Bool { history.captureBusy || history.recording || history.annotating || history.loading || history.fault }
    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                Button { history.capture?(.area) } label: { Label(history.captureBusy ? "Capture…" : "Capturer une zone", systemImage: "viewfinder").padding(.horizontal, 13).frame(height: 40) }
                    .buttonStyle(FullAreaButtonStyle()).disabled(unavailable)
                Rectangle().fill(Theme.onAccent.opacity(0.3)).frame(width: 1, height: 24)
                Menu { ForEach([CaptureAction.area, .window, .screen], id: \.self) { action in Button(action.title) { history.capture?(action) } } }
                label: { Image(systemName: "chevron.down").foregroundColor(Theme.onAccent).frame(width: 29, height: 40).contentShape(Rectangle()) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(unavailable).accessibilityLabel("Autres captures d’écran")
            }.foregroundStyle(Theme.onAccent).background { RoundedRectangle(cornerRadius: 10).fill(palette.actionGradient).glassControlFinish(radius: 10, primary: true) }.opacity(unavailable ? 0.45 : 1)
            Button { history.capture?(.text) } label: { Label("Extraire du texte", systemImage: "text.viewfinder") }.buttonStyle(PasteButtonStyle()).disabled(unavailable)
            Button { if history.recording { history.stopRecording?() } else { history.capture?(.video) } } label: { Label(history.recording ? "Arrêter" : "Vidéo", systemImage: history.recording ? "stop.circle.fill" : "video") }
                .buttonStyle(PasteButtonStyle()).foregroundStyle(history.recording ? Theme.danger : Theme.ink).disabled(unavailable && !history.recording)
        }.font(.system(size: 12, weight: .semibold)).fixedSize()
    }
}

struct LibraryFilters: View {
    @ThemePalette private var palette
    @ObservedObject var history: History
    @Binding var listLayout: Bool
    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    filter("Tout", kind: nil)
                    ForEach([ClipKind.text, .image, .link, .file, .video, .color], id: \.self) { filter($0.label, kind: $0) }
                }
            }.fixedSize(horizontal: false, vertical: true)
            Menu {
                Button("Toutes les applications") { history.sourceFilter = "" }
                ForEach(history.sources, id: \.self) { source in Button(source) { history.sourceFilter = source } }
                Divider(); Toggle("Aujourd’hui uniquement", isOn: $history.todayOnly)
            } label: { Label(history.sourceFilter.isEmpty ? (history.todayOnly ? "Aujourd’hui" : "Application") : history.sourceFilter, systemImage: "line.3.horizontal.decrease").lineLimit(1).padding(9).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).fixedSize().frame(maxWidth: 170).tint(palette.chromeAccent).help("Filtrer par application ou par date")
            HStack(spacing: 2) {
                layoutButton("square.grid.2x2", label: "Vue en grille", isList: false)
                layoutButton("list.bullet", label: "Vue en liste", isList: true)
            }.padding(3)
        }.font(.system(size: 12))
    }
    private func filter(_ label: String, kind: ClipKind?) -> some View {
        let selected = history.filter == kind
        return Button { history.filter = kind } label: {
            Text(label).font(.system(size: 12, weight: selected ? .semibold : .regular)).padding(.horizontal, 12).frame(height: 38)
                .foregroundStyle(selected ? palette.chromeAccent : Theme.chromeSecondary)
                .overlay(alignment: .bottom) {
                    if selected { Capsule().fill(palette.chromeAccent).frame(height: 2).padding(.horizontal, 9).allowsHitTesting(false) }
                }
        }.buttonStyle(FullAreaButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func layoutButton(_ icon: String, label: String, isList: Bool) -> some View {
        Button { listLayout = isList } label: {
            Image(systemName: icon).frame(width: 31, height: 30).foregroundStyle(listLayout == isList ? Theme.onAccent : Theme.chromeSecondary)
                .background { if listLayout == isList { RoundedRectangle(cornerRadius: 7).fill(palette.actionGradient).glassControlFinish(radius: 7, primary: true) } }
        }.buttonStyle(FullAreaButtonStyle()).help(label).accessibilityLabel(label).accessibilityAddTraits(listLayout == isList ? .isSelected : [])
    }
}

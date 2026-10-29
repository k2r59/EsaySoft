import SwiftUI
import AppKit

@main struct EasyMusicApp: App {
    @StateObject private var store = MusicStore()
    @StateObject private var updates = AppUpdates()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).environmentObject(updates).preferredColorScheme(.dark)
                .frame(minWidth: 1060, minHeight: 720)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); updates.busy = { store.activeTitle != nil || !store.pending.isEmpty || store.exporting || store.importingPlaylist || store.isPlaying || store.previewLoadingID != nil }; updates.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher une mise à jour…") { updates.check() }.disabled(!updates.canCheck)
            }
            CommandGroup(after: .newItem) {
                Button("Rechercher") { store.section = "search" }.keyboardShortcut("f")
                Button("Afficher le dossier musical") { NSWorkspace.shared.open(store.folder) }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.035)
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.075)
    static let card = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let green = Color(red: 0.12, green: 0.85, blue: 0.39)
    static let secondary = Color(white: 0.70)
}
struct Art: View {
    let url: String?
    var size: CGFloat = 48
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack {
                LinearGradient(colors: [Color(red: 0.21, green: 0.34, blue: 0.28), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.28, weight: .light)).foregroundStyle(.white.opacity(0.65))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size > 100 ? 8 : 4)).accessibilityHidden(true)
    }
}
struct GreenButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
            .padding(.horizontal, 23).padding(.vertical, 14)
            .background(Theme.green.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}
struct ContentView: View {
    @EnvironmentObject var store: MusicStore
    @EnvironmentObject var updates: AppUpdates
    @State private var importPlaylist = false
    @State private var renamingPlaylist: Playlist?
    @State private var renamedValue = ""
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var playlistTrack: LocalTrack?
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                sidebar.frame(width: 225)
                VStack(spacing: 0) {
                    topbar
                    if let notice = store.notice {
                        NoticeBanner(title: store.noticeIsWarning ? "Action requise" : "Information", message: notice, warning: store.noticeIsWarning, dismiss: { store.notice = nil })
                            .padding(.horizontal, 24).padding(.bottom, 12)
                    }
                    if store.section == "home" { home }
                    else if store.section == "search" { searchContent }
                    else if store.section == "settings" { settings }
                    else { libraryContent }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
                if let track = store.selected { TrackDetailsView(track: track).frame(width: 310).transition(.move(edge: .trailing).combined(with: .opacity)) }
            }.padding(.horizontal, 8).padding(.top, 30).padding(.bottom, 8)
            playerBar.frame(height: 92)
        }
        .background(Theme.background).tint(Theme.green)
        .task { await store.checkPlaylistUpdates() }
        .task { await store.refreshLocalBitrates() }
        .onReceive(Timer.publish(every: 900, on: .main, in: .common).autoconnect()) { _ in
            Task { await store.checkPlaylistUpdates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.checkPlaylistUpdates() }
        }
        .sheet(item: $renamingPlaylist) { playlist in
            VStack(alignment: .leading, spacing: 20) {
                Text("Renommer la playlist").font(.title2.bold())
                TextField("Nom", text: $renamedValue).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Annuler") { renamingPlaylist = nil }
                    Spacer()
                    Button("Enregistrer") { store.renamePlaylist(playlist.id, to: renamedValue); renamingPlaylist = nil }
                        .buttonStyle(GreenButton()).disabled(renamedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 400)
        }
        .sheet(isPresented: $importPlaylist) { ImportPlaylistSheet().environmentObject(store) }
        .sheet(isPresented: $newPlaylist) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Une nouvelle playlist").font(.title2.bold())
                TextField("Nom de la playlist", text: $playlistName).textFieldStyle(.roundedBorder).onSubmit { createPlaylist() }
                HStack { Button("Annuler") { newPlaylist = false; playlistTrack = nil }; Spacer(); Button("Créer") { createPlaylist() }.buttonStyle(GreenButton()).disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }.padding(28).frame(width: 380)
        }
    }
    func createPlaylist() {
        store.createPlaylist(playlistName)
        if let track = playlistTrack, let playlist = store.library.playlists.last { store.add(track, to: playlist.id) }
        playlistName = ""; playlistTrack = nil; newPlaylist = false
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 32)).foregroundStyle(Theme.green)
                Text("EasyMusic").font(.system(size: 23, weight: .bold, design: .rounded))
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 26)
            nav("Accueil", icon: "house.fill", section: "home")
            nav("Rechercher", icon: "magnifyingglass", section: "search")
            HStack {
                Label("Votre bibliothèque", systemImage: "books.vertical").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
                Button { newPlaylist = true } label: { Image(systemName: "plus").frame(width: 24, height: 24) }.buttonStyle(.plain).help("Créer une playlist")
            }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12)
            Button { importPlaylist = true } label: {
                Label(store.importingPlaylist ? "Import en cours…" : "Importer une playlist", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 8)
            }.buttonStyle(.plain).disabled(store.importingPlaylist)
            nav("Tous les titres", icon: "arrow.down.circle.fill", section: "library")
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.library.playlists) { list in
                        Button { store.section = list.id.uuidString } label: {
                            HStack(spacing: 12) {
                                PlaylistArtwork(playlist: list).environmentObject(store)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                    Text("Playlist · \(list.importedTracks?.count ?? list.trackIDs.count) titres").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                }; Spacer(minLength: 0)
                                if list.hasRemoteChanges == true {
                                    Circle().fill(Theme.green).frame(width: 9, height: 9)
                                        .help("La playlist d’origine a changé").accessibilityLabel("Mise à jour disponible")
                                }
                            }.padding(8).background(store.section == list.id.uuidString ? Theme.card : .clear).cornerRadius(6)
                        }.buttonStyle(.plain).contextMenu {
                            Button("Renommer") { renamedValue = list.name; renamingPlaylist = list }
                            Button("Choisir une pochette…") { store.chooseArtwork(for: list.id) }
                            if list.artworkPath != nil { Button("Pochette du premier titre") { store.resetArtwork(for: list.id) } }
                            if list.sourceURL != nil {
                                Button("Vérifier les changements") { Task { await store.refreshPlaylist(list.id, apply: false) } }
                                Button("Synchroniser") { Task { await store.refreshPlaylist(list.id, apply: true) } }
                            }
                        }
                    }
                    if store.library.playlists.isEmpty {
                        Button("Créer une playlist") { newPlaylist = true }.buttonStyle(.bordered).tint(.white).padding(.top, 12)
                    }
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            nav("Sources et réglages", icon: "slider.horizontal.3", section: "settings")
            Spacer().frame(height: 12)
        }.frame(maxHeight: .infinity).background(Theme.surface).cornerRadius(10)
    }
    func nav(_ title: String, icon: String, section: String) -> some View {
        Button { store.section = section; if section == "search" { searchFocused = true } } label: {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(store.section == section ? .white : Theme.secondary)
                .background(store.section == section ? Theme.card : .clear).cornerRadius(6)
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }
    var topbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 19)).foregroundStyle(Theme.secondary)
                TextField(store.searchMode.placeholder, text: $store.query).textFieldStyle(.plain).font(.system(size: 14))
                    .focused($searchFocused).onSubmit { store.search() }.accessibilityLabel("Rechercher un morceau ou coller un lien")
                if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Effacer la recherche") }
            }.padding(14).background(Color(white: 0.16), in: Capsule())
            Button { store.search() } label: { Image(systemName: "arrow.right").font(.system(size: 17, weight: .bold)).frame(width: 42, height: 42).background(Theme.card, in: Circle()) }.buttonStyle(.plain).help("Rechercher").disabled(store.query.trimmingCharacters(in: .whitespaces).isEmpty && store.searchMode != .genres)
        }.padding(24)
    }
    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !store.homeMixes.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(store.homeShortcuts) { item in
                            Button { store.openCollection(item) } label: {
                                HStack(spacing: 10) {
                                    Art(url: item.artwork, size: 48)
                                    Text(item.name).font(.system(size: 12, weight: .bold)).lineLimit(2)
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.12)).cornerRadius(5)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if store.homeLoading && store.discoveries.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                if let featured = store.discoveries.first {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("À la une").font(.system(size: 23, weight: .bold))
                            HStack(spacing: 16) {
                                Art(url: featured.artwork, size: 172)
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(featured.artist).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                    Text(featured.title).font(.system(size: 25, weight: .bold)).lineLimit(3)
                                    HStack(spacing: 16) {
                                        Button { store.preview(featured) } label: {
                                            Image(systemName: store.previewing?.id == featured.id && store.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(.black).frame(width: 34, height: 34).background(.white, in: Circle())
                                        }.buttonStyle(.plain).help("Écouter un extrait")
                                        downloadControl(featured)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Mix à découvrir").font(.system(size: 23, weight: .bold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 18) { ForEach(store.homeMixes) { collectionCard($0) } }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !store.personalMixes.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Pour vous").font(.system(size: 23, weight: .bold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 18) { ForEach(store.personalMixes) { collectionCard($0) } }
                        }
                    }
                }
                if let recent = store.library.recentCollections, !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Récents").font(.system(size: 23, weight: .bold))
                        ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 18) { ForEach(recent) { collectionCard($0) } } }
                    }
                }
                if !store.discoveries.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Text("Hits du moment").font(.system(size: 23, weight: .bold)); Spacer(); Text("Deezer").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 18) {
                                ForEach(store.discoveries) { track in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Button { store.showHomeTrack(track) } label: { Art(url: track.artwork, size: 154) }.buttonStyle(.plain)
                                        Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                        HStack {
                                            Text(track.artist).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                                            Spacer(minLength: 0)
                                            Button { store.preview(track) } label: { Image(systemName: store.previewing?.id == track.id && store.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain).help("Écouter un extrait")
                                        }
                                    }.frame(width: 154)
                                }
                            }
                        }
                    }
                }
                if !store.homeGenres.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Genres").font(.system(size: 23, weight: .bold))
                        ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 18) { ForEach(store.homeGenres) { collectionCard($0) } } }
                    }
                }
                if !store.homeLoading && store.discoveries.isEmpty {
                    Text("Catalogue indisponible").foregroundStyle(Theme.secondary)
                    Button("Réessayer") { Task { await store.loadDiscoveries(force: true) } }
                }
            }.padding(.horizontal, 24).padding(.bottom, 32)
                .background(LinearGradient(colors: [Color(red: 0.19, green: 0.27, blue: 0.29).opacity(0.6), .clear], startPoint: .top, endPoint: .center))
        }.task { await store.loadDiscoveries() }
    }
    func collectionCard(_ item: CatalogItem) -> some View {
        Button { store.openCollection(item) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Art(url: item.artwork, size: 154)
                Text(item.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1) }
            }.frame(width: 154, alignment: .topLeading)
        }.buttonStyle(.plain)
    }
    var searchContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                ForEach(SearchMode.allCases) { mode in
                    Button { store.changeMode(mode) } label: {
                        Text(mode.rawValue).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(store.searchMode == mode ? Color.white : Theme.card, in: Capsule()).foregroundStyle(store.searchMode == mode ? .black : .white)
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            } }
            HStack {
                Text(store.collectionTitle ?? (store.searched ? "Résultats" : "Rechercher")).font(.system(size: 24, weight: .bold)).lineLimit(2)
                Spacer()
                if store.searching { ProgressView().controlSize(.small) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SearchResultsView()
                    if store.visibleResults.isEmpty && store.catalogItems.isEmpty {
                        empty(icon: store.searching ? "waveform" : "magnifyingglass", title: store.searching ? "Recherche…" : store.searched ? "Aucun résultat" : "Un titre, un artiste ou un lien", subtitle: "").frame(minHeight: 280)
                    }
                }
            }
        }.padding(.horizontal, 24).padding(.bottom, 24)
    }
    func trackRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            Button { store.select(track) } label: {
                HStack(spacing: 12) {
                    Art(url: track.artwork)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Text(track.artist).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }; Spacer(minLength: 0)
                }
            }.buttonStyle(.plain)
            TrackPlaybackButtons(track: track).environmentObject(store)
            Text(track.durationLabel).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.secondary)
            downloadControl(track)
        }.padding(9).background(store.selected?.id == track.id ? Color(white: 0.22) : Theme.card.opacity(0.35)).cornerRadius(6)
    }
    @ViewBuilder func downloadControl(_ track: Track) -> some View {
        if let local = store.downloaded(track) {
            Menu {
                Button("Lire le fichier local") { store.play(local) }
                playlistMenu(local)
            } label: { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.green) }
                .menuStyle(.borderlessButton).frame(width: 34).help("Déjà téléchargé · Ajouter à une playlist")
        } else if store.isQueued(track) {
            Image(systemName: "clock").font(.system(size: 22)).foregroundStyle(Theme.secondary).frame(width: 34, height: 38).accessibilityLabel("Téléchargement en cours ou en attente")
        } else {
            Button { store.enqueue(track) } label: { Image(systemName: "arrow.down.circle").font(.system(size: 22)).foregroundStyle(Theme.green).frame(width: 34, height: 38) }.buttonStyle(.plain).help("Télécharger")
        }
    }
    func playlistMenu(_ local: LocalTrack) -> some View {
        Menu("Ajouter aux playlists") {
            ForEach(store.library.playlists) { list in
                Toggle(list.name, isOn: Binding(get: { list.trackIDs.contains(local.id) }, set: { value in if value { store.add(local, to: list.id) } else { store.remove(local, from: list.id) } }))
            }
            Divider()
            Button("Nouvelle playlist…") { playlistTrack = local; newPlaylist = true }
        }
    }
    var libraryContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom, spacing: 22) {
                if let playlist = store.currentPlaylist {
                    Button { store.chooseArtwork(for: playlist.id) } label: {
                        PlaylistArtwork(playlist: playlist, size: 140).environmentObject(store)
                    }.buttonStyle(.plain).help("Choisir une pochette")
                } else {
                    Art(url: store.visibleLocal.first?.track.artwork, size: 140)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.currentPlaylist == nil ? "BIBLIOTHÈQUE LOCALE" : "PLAYLIST").font(.system(size: 11, weight: .bold)).tracking(1.4)
                    Text(store.currentPlaylist?.name ?? "Tous vos titres").font(.system(size: 38, weight: .heavy)).lineLimit(2)
                    Text(store.currentPlaylist?.importedTracks != nil ? "\(store.currentPlaylist?.importedTracks?.count ?? 0) titres · \(store.visibleLocal.count) en local" : "\(store.visibleLocal.count) titres · Disponibles hors connexion").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { if let first = store.visibleLocal.first { store.play(first) } } label: { Label("Lire", systemImage: "play.fill") }
                        .buttonStyle(GreenButton()).disabled(store.visibleLocal.isEmpty)
                    if let list = store.currentPlaylist, list.importedTracks != nil {
                        Button { store.downloadPlaylist(list) } label: { Image(systemName: "arrow.down.circle").font(.system(size: 20)) }
                            .buttonStyle(ToolbarButtonStyle()).help("Télécharger les titres manquants").accessibilityLabel("Télécharger les titres manquants")
                            .disabled(!store.playlistTracks(list).contains { store.downloaded($0) == nil && !store.isQueued($0) })
                    }
                    Button { store.exportForMobile() } label: { Label(store.exporting ? "Préparation…" : "Pour Offline Music", systemImage: "iphone.and.arrow.forward") }
                        .buttonStyle(ToolbarButtonStyle()).disabled(store.exporting || store.visibleLocal.isEmpty)
                    if let list = store.currentPlaylist {
                        Menu {
                            Button("Renommer") { renamedValue = list.name; renamingPlaylist = list }
                            Button("Choisir une pochette…") { store.chooseArtwork(for: list.id) }
                            Button("Pochette du premier titre") { store.resetArtwork(for: list.id) }
                            if let raw = list.sourceURL, let url = URL(string: raw) {
                                Divider()
                                Link("Voir la source", destination: url)
                                Button("Vérifier les modifications") { Task { await store.refreshPlaylist(list.id, apply: false) } }
                            }
                        } label: { Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 44) }
                            .menuStyle(.borderlessButton).fixedSize().help("Options de la playlist")
                        if list.sourceURL != nil {
                            Button { Task { await store.refreshPlaylist(list.id, apply: true) } } label: {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18))
                                    .overlay(alignment: .topTrailing) { if list.hasRemoteChanges == true { Circle().fill(Theme.green).frame(width: 7, height: 7).offset(x: 5, y: -5) } }
                            }.buttonStyle(ToolbarButtonStyle()).disabled(store.checkingPlaylists.contains(list.id))
                                .help("Synchroniser avec la playlist originale").accessibilityLabel("Synchroniser la playlist")
                        }
                    }
                }.padding(.vertical, 2)
            }
            if let playlist = store.currentPlaylist, playlist.importedTracks != nil {
                ImportedPlaylistView(playlist: playlist).environmentObject(store)
            } else if store.visibleLocal.isEmpty {
                empty(icon: "music.note.list", title: "Aucun titre", subtitle: store.currentPlaylist == nil ? "Les titres téléchargés apparaîtront ici." : "Ajoutez des titres depuis votre bibliothèque avec le menu •••.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.visibleLocal) { local in
                            HStack(spacing: 12) {
                                PlayableArtwork(track: local.track)
                                VStack(alignment: .leading, spacing: 5) { Button { store.select(local.track) } label: { Text(local.track.title).font(.system(size: 14, weight: .medium)).lineLimit(1) }.buttonStyle(.plain); Text(local.track.artist).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1) }
                                Spacer()
                                TrackPlaybackButtons(track: local.track, compact: true, showPlay: false).environmentObject(store)
                                PlaylistAddButton(track: local.track)
                                Text(local.bitrateLabel).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.secondary).help("Débit mesuré dans le fichier, approximatif pour les formats à débit variable")
                                Text(URL(fileURLWithPath: local.path).pathExtension.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.secondary)
                                Menu {
                                    Button("Lire") { store.play(local) }
                                    Menu("Ajouter à une playlist") {
                                        ForEach(store.library.playlists) { list in
                                            Toggle(list.name, isOn: Binding(get: { list.trackIDs.contains(local.id) }, set: { value in if value { store.add(local, to: list.id) } else { store.remove(local, from: list.id) } }))
                                        }
                                    }.disabled(store.library.playlists.isEmpty)
                                    if let list = store.currentPlaylist { Button("Retirer de cette playlist") { store.remove(local, from: list.id) } }
                                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: local.path)]) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28).help("Actions du morceau")
                            }.padding(10).background(Theme.card.opacity(0.5)).cornerRadius(6)
                        }
                    }
                }
            }
        }.padding(.horizontal, 24).padding(.bottom, 24)
    }
    func empty(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44, weight: .light)).foregroundStyle(Theme.secondary)
            Text(title).font(.system(size: 21, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
    var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Réglages").font(.system(size: 27, weight: .bold))
                Text("Aucun compte ni abonnement requis. La disponibilité dépend de chaque source.").foregroundStyle(Theme.secondary)
                GroupBox("Téléchargements") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Text("Enregistrer dans"); Spacer(); Button("Choisir un dossier…") { store.chooseFolder() } }
                        Text(store.folder.path).font(.caption).foregroundStyle(Theme.secondary).textSelection(.enabled)
                        Picker("Format de sortie", selection: $store.exportFormat) {
                            Text("Original — qualité préservée").tag("original")
                            if store.canConvert { Text("MP3 — compatibilité maximale").tag("mp3"); Text("M4A — appareils Apple").tag("m4a") }
                        }
                        Text(store.canConvert ? "Conversion et métadonnées disponibles avec FFmpeg. Convertir n’améliore pas la qualité de la source." : "Le format original est disponible. Installez FFmpeg pour activer MP3, M4A et l’intégration des pochettes.").font(.caption).foregroundStyle(Theme.secondary)
                    }.padding(12)
                }
                GroupBox("Accueil") {
                    HStack {
                        Text("Les suggestions suivent vos recherches et vos écoutes.").foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("Réinitialiser les suggestions") { store.resetRecommendations() }
                            .disabled((store.library.interests ?? []).isEmpty)
                    }.padding(10)
                }
                GroupBox("Sources") {
                    VStack(alignment: .leading, spacing: 14) {
                        sourceLine("YouTube · SoundCloud", detail: "Recherche et téléchargement via yt-dlp", icon: "checkmark.circle.fill")
                        sourceLine("Deezer", detail: "Recherche de titres et extraits. Audio complet recherché sur d’autres sources.", icon: "checkmark.circle.fill")
                        sourceLine("Spotify", detail: "Identification d’un titre par lien public. Pas de recherche du catalogue ni d’extraction du flux Spotify.", icon: "link")
                        sourceLine("Bandcamp · Jamendo · Audiomack", detail: "Liens de morceaux reconnus par le moteur", icon: "link")
                        sourceLine("Internet Archive · Vimeo · Mixcloud", detail: "Liens pris en charge selon les formats accessibles", icon: "link")
                    }.padding(12)
                }
                GroupBox("Offline Music sur iPhone") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Depuis une playlist ou la bibliothèque, « Pour Offline Music » prépare les fichiers à importer. Choisissez iCloud Drive ou un dossier local.")
                        Text("Sur l’iPhone : Import → Files, ou Import → Computer pour un transfert Wi-Fi. Les playlists doivent être recréées dans Offline Music ; aucune synchronisation automatique n’est annoncée.").foregroundStyle(Theme.secondary)
                        Link("Consulter les instructions officielles ↗", destination: URL(string: "https://musicplayeroffline.com/faq/import")!)
                    }.font(.system(size: 12)).padding(12)
                }
                Text("Téléchargez les contenus que vous êtes autorisé à conserver. Les contenus protégés ou exigeant une connexion ne sont pas déverrouillés.").font(.caption).foregroundStyle(Theme.secondary)
                GroupBox("Mises à jour") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Vérifier automatiquement", isOn: Binding(get: { updates.automaticChecks }, set: updates.setAutomaticChecks)).disabled(!updates.available)
                        Button(updates.waitingToInstall ? "Installer et relancer" : "Rechercher une mise à jour…") {
                            if updates.waitingToInstall { updates.installWhenReady() } else { updates.check() }
                        }.disabled(!updates.waitingToInstall && !updates.canCheck)
                        if !updates.message.isEmpty { Text(updates.message).font(.caption).foregroundStyle(Theme.secondary) }
                    }.padding(12)
                }
                Text("EasyMusic \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · yt-dlp 2026.10.26").font(.caption).foregroundStyle(Theme.secondary)
            }.padding(24)
        }
    }
    func sourceLine(_ name: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Image(systemName: icon).foregroundStyle(Theme.green); VStack(alignment: .leading, spacing: 5) { Text(name).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }; Spacer() }
    }
    var playerBar: some View { SpotifyPlayerBar().environmentObject(store) }
    func time(_ value: Double) -> String { guard value.isFinite, value >= 0 else { return "0:00" }; return String(format: "%d:%02d", Int(value)/60, Int(value)%60) }
}

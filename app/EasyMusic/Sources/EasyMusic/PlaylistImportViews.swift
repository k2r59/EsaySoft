import SwiftUI

struct ImportPlaylistSheet: View {
    @EnvironmentObject var store: MusicStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Importer une playlist").font(.title2.bold())
            Text("Spotify · Deezer · YouTube Music").foregroundStyle(Theme.secondary)
            TextField("Collez le lien de la playlist", text: $link).textFieldStyle(.roundedBorder)
                .disabled(store.importingPlaylist).onSubmit { start() }
            Text("Playlists accessibles sans connexion. Le téléchargement se lance ensuite depuis la playlist.")
                .font(.caption).foregroundStyle(Theme.secondary)
            if store.importingPlaylist { ProgressView("Récupération des titres…") }
            if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(Theme.secondary).textSelection(.enabled) }
            HStack {
                Button("Fermer") { dismiss() }.disabled(store.importingPlaylist)
                Spacer()
                Button("Importer") { start() }.buttonStyle(GreenButton())
                    .disabled(store.importingPlaylist || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 460).interactiveDismissDisabled(store.importingPlaylist)
    }
    private func start() {
        guard !store.importingPlaylist, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            if await store.importPlaylist(link) { dismiss() }
        }
    }
}

struct ImportedPlaylistView: View {
    @EnvironmentObject var store: MusicStore
    let playlist: Playlist
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { store.downloadPlaylist(playlist) } label: { Label("Télécharger les titres manquants", systemImage: "arrow.down.circle") }
                    .buttonStyle(GreenButton())
                    .disabled(!(playlist.importedTracks ?? []).contains { store.downloaded($0) == nil && !store.isQueued($0) })
                Spacer()
                if let raw = playlist.sourceURL, let url = URL(string: raw) { Link("Voir la source", destination: url) }
            }
            if let warning = playlist.importWarning { Text(warning).font(.caption).foregroundStyle(Theme.secondary) }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.playlistTracks(playlist)) { track in
                        HStack(spacing: 12) {
                            Button {
                                if let local = store.downloaded(track) { store.play(local) } else { store.preview(track) }
                            } label: { Image(systemName: "play.fill").frame(width: 30, height: 40) }
                                .buttonStyle(.plain).help("Écouter")
                            Art(url: track.artwork, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).lineLimit(1)
                                Text(store.downloadErrors[track.id] ?? track.artist).font(.caption).foregroundStyle(Theme.secondary).lineLimit(2)
                            }
                            Spacer()
                            if store.downloaded(track) != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).help("Disponible hors connexion")
                                if let local = store.downloaded(track) {
                                    Menu {
                                        ForEach(store.library.playlists) { list in
                                            if list.id != playlist.id {
                                                Toggle(list.name, isOn: Binding(get: { list.trackIDs.contains(local.id) }, set: { value in
                                                    if value { store.add(local, to: list.id) } else { store.remove(local, from: list.id) }
                                                }))
                                            }
                                        }
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28).help("Ajouter à une autre playlist")
                                }
                            } else if store.isQueued(track) {
                                ProgressView().controlSize(.small).help(store.activeID == track.id ? "Téléchargement en cours" : "En attente")
                            } else {
                                Button { store.enqueue(track) } label: { Image(systemName: store.downloadErrors[track.id] == nil ? "arrow.down.circle" : "arrow.clockwise") }
                                    .buttonStyle(.plain).help(store.downloadErrors[track.id] == nil ? "Télécharger" : "Réessayer")
                            }
                        }.padding(10).background(Theme.card.opacity(0.5)).cornerRadius(6)
                    }
                }
            }
        }
    }
}

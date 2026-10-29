import SwiftUI
import AppKit

struct ImportPlaylistSheet: View {
    @EnvironmentObject var store: MusicStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Importer une playlist").font(.system(size: 23, weight: .bold))
                    Text("Spotify · Deezer · YouTube Music").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary).frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.07), in: Circle())
                }.buttonStyle(.plain).disabled(store.importingPlaylist).help("Fermer").accessibilityLabel("Fermer l’import")
                    .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "link").font(.system(size: 18)).foregroundStyle(Theme.secondary)
                    TextField("Collez le lien de la playlist", text: $link).textFieldStyle(.plain)
                        .font(.system(size: 15)).focused($focused).onSubmit { start() }
                        .accessibilityLabel("Lien de la playlist")
                    Button("Coller") {
                        if let value = NSPasteboard.general.string(forType: .string) { link = value; focused = true }
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                }.padding(.horizontal, 16).frame(height: 54)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Theme.green : Color.white.opacity(0.15), lineWidth: focused ? 1.5 : 1))
                    .disabled(store.importingPlaylist)
                Text("Playlist publique ou accessible par lien.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            if store.importingPlaylist {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Récupération des titres…").font(.system(size: 13)) }
            }
            if let error { NoticeBanner(title: "Import impossible", message: error, warning: true) }
            HStack {
                Spacer()
                Button { start() } label: {
                    HStack(spacing: 10) { Text("Importer"); Image(systemName: "arrow.right") }
                }.buttonStyle(GreenButton())
                    .disabled(store.importingPlaylist || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 520).background(Theme.surface)
            .interactiveDismissDisabled(store.importingPlaylist).onAppear { focused = true }
    }
    private func start() {
        guard !store.importingPlaylist, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        error = nil
        Task {
            if await store.importPlaylist(link) { dismiss() }
            else { error = store.notice ?? "Cette playlist n’a pas pu être importée." }
        }
    }
}

struct ImportedPlaylistView: View {
    @EnvironmentObject var store: MusicStore
    let playlist: Playlist
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.syncErrors[playlist.id] {
                NoticeBanner(title: "Vérification impossible", message: error, warning: true)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.playlistTracks(playlist)) { track in
                        HStack(spacing: 12) {
                            TrackPlayButton(track: track)
                            TrackArtworkButton(track: track, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Button { store.select(track) } label: { Text(track.title).lineLimit(1) }.buttonStyle(.plain)
                                Text(track.artist).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                            Spacer()
                            TrackPlaybackButtons(track: track, compact: true, showPlay: false).environmentObject(store)
                            LikeButton(track: track)
                            PlaylistAddButton(track: track)
                            if let local = store.downloaded(track) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).help("Disponible hors connexion")
                                Menu {
                                    ForEach(store.library.playlists) { list in
                                        if list.id != playlist.id {
                                            Toggle(list.name, isOn: Binding(get: { store.contains(local.track, in: list) }, set: { value in
                                                if value { store.add(local, to: list.id) } else { store.remove(local, from: list.id) }
                                            }))
                                        }
                                    }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28).help("Ajouter à une autre playlist")
                            } else if store.isQueued(track) {
                                ProgressView().controlSize(.small).help(store.activeDownloads.contains { $0.id == track.id } ? "Téléchargement en cours" : "En attente")
                            } else {
                                Button { store.enqueue(track) } label: { Image(systemName: store.downloadErrors[track.id] == nil ? "arrow.down.circle" : "arrow.clockwise") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(store.downloadErrors[track.id] == nil ? Theme.secondary : .orange)
                                    .help(store.downloadErrors[track.id].map { "Réessayer : \($0)" } ?? "Télécharger")
                                    .accessibilityLabel(store.downloadErrors[track.id] == nil ? "Télécharger \(track.title)" : "Réessayer le téléchargement de \(track.title)")
                            }
                        }.padding(10).background(Theme.card.opacity(0.5)).cornerRadius(6)
                    }
                }
            }
        }
    }
}

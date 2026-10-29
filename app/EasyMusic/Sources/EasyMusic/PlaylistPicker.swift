import SwiftUI

extension MusicStore {
    func contains(_ track: Track, in list: Playlist) -> Bool {
        playlistTracks(list).contains { $0.id == track.id || Matching.sameRecording($0, track) }
    }
    func setMembership(_ track: Track, in id: UUID, included: Bool) {
        guard let index = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        if included {
            guard !contains(track, in: library.playlists[index]) else { return }
            if let local = downloaded(track) { library.playlists[index].trackIDs.append(local.id) }
            else {
                if library.playlists[index].importedTracks == nil { library.playlists[index].importedTracks = [] }
                library.playlists[index].importedTracks?.append(track)
                enqueue(track)
            }
        } else {
            library.playlists[index].importedTracks?.removeAll { $0.id == track.id || Matching.sameRecording($0, track) }
            let ids = Set(library.tracks.filter { $0.track.id == track.id || Matching.sameRecording($0.track, track) }.map(\.id))
            library.playlists[index].trackIDs.removeAll { ids.contains($0) }
        }
        save()
    }
}

struct PlaylistAddButton: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "plus.circle").font(.system(size: 21)).frame(width: 36, height: 36)
        }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            .help("Ajouter aux playlists").accessibilityLabel("Ajouter \(track.title) aux playlists")
            .popover(isPresented: $presented, arrowEdge: .top) { PlaylistPicker(track: track).environmentObject(store) }
    }
}
struct PlaylistPicker: View {
    @EnvironmentObject var store: MusicStore
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var query = ""
    @State private var creating = false
    @State private var name = ""
    var lists: [Playlist] { store.library.playlists.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ajouter à une playlist").font(.system(size: 14, weight: .bold))
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Rechercher une playlist", text: $query).textFieldStyle(.plain)
            }.padding(12).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            if creating {
                HStack {
                    TextField("Nom de la playlist", text: $name).textFieldStyle(.plain).onSubmit { create() }
                    Button(action: create) { Image(systemName: "checkmark") }.buttonStyle(.plain).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Créer la playlist")
                }.padding(12).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            } else {
                Button { creating = true } label: { Label("Nouvelle playlist", systemImage: "plus") }.buttonStyle(.plain)
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(lists) { list in
                        Button { store.setMembership(track, in: list.id, included: !store.contains(track, in: list)) } label: {
                            HStack(spacing: 12) {
                                PlaylistArtwork(playlist: list, size: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name).lineLimit(1)
                                    Text("\(store.playlistTracks(list).count) titres").font(.caption).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: store.contains(track, in: list) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.contains(track, in: list) ? Theme.green : Theme.secondary)
                            }.padding(6).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(store.contains(track, in: list) ? "Ajouté" : "Non ajouté")
                    }
                    if lists.isEmpty { Text("Aucune playlist").foregroundStyle(Theme.secondary).padding() }
                }
            }.frame(maxHeight: 290)
            HStack { Spacer(); Button("Terminé") { dismiss() }.buttonStyle(.plain).fontWeight(.semibold) }
        }.padding(20).frame(width: 310).background(Theme.surface)
    }
    private func create() {
        if let id = store.createPlaylist(name, navigate: false) {
            store.setMembership(track, in: id, included: true); name = ""; creating = false; query = ""
        }
    }
}
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).frame(height: 44)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.07), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }
}

import SwiftUI

struct TrackDetailsView: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    @State private var artists: [CatalogItem] = []
    @State private var albums: [CatalogItem] = []
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("À propos du titre").font(.system(size: 14, weight: .bold))
                    Spacer()
                    Button { store.selected = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                        .buttonStyle(.plain).help("Fermer").accessibilityLabel("Fermer les détails")
                }
                PlayableArtwork(track: track, size: 274)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(track.title).font(.system(size: 26, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Text(track.artist).font(.system(size: 15)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    PlaylistAddButton(track: track)
                }
                TrackPlaybackButtons(track: track, showPlay: false)
                if let local = store.downloaded(track) {
                    Label("En local · \(local.bitrateLabel)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.system(size: 13))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Qualité audio").fontWeight(.semibold); if store.inspecting { ProgressView().controlSize(.small) } }
                        Picker("Qualité", selection: $store.selectedFormat) {
                            Text("Meilleure disponible").tag("best")
                            ForEach(store.formats) { Text($0.label).tag($0.id) }
                        }.labelsHidden()
                        Button { store.enqueue(track) } label: {
                            Label(store.isQueued(track) ? "Dans la file" : "Télécharger", systemImage: store.isQueued(track) ? "clock" : "arrow.down")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(GreenButton()).disabled(store.isQueued(track))
                    }
                }
                if loading { ProgressView().controlSize(.small) }
                if !artists.isEmpty {
                    Text("Artiste").font(.headline)
                    ForEach(artists) { item in detailLink(item) }
                }
                if !albums.isEmpty {
                    Text("Albums de l’artiste").font(.headline)
                    ForEach(albums) { item in detailLink(item) }
                }
                if let url = URL(string: track.url) {
                    Link("Voir sur \(track.source) ↗", destination: url).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }.padding(18)
        }.background(Theme.surface).cornerRadius(10)
            .task(id: track.id) {
                artists = []; albums = []; loading = true
                defer { loading = false }
                let found = (try? await Catalog.search(track.artist, mode: .artists)) ?? []
                guard !Task.isCancelled else { return }
                artists = Array(found.filter { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == track.artist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }.prefix(1))
                if let artist = artists.first {
                    let rows = try? await Catalog.rows("artist/\(artist.key)/albums", query: [URLQueryItem(name: "limit", value: "4")])
                    guard !Task.isCancelled else { return }
                    albums = Catalog.items(rows ?? [], kind: "album")
                }
            }
    }
    private func detailLink(_ item: CatalogItem) -> some View {
        Button { store.openCollection(item) } label: {
            HStack(spacing: 12) {
                Art(url: item.artwork, size: 56)
                    .clipShape(RoundedRectangle(cornerRadius: item.kind == "artist" ? 28 : 4))
                Text(item.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
            }.padding(10).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

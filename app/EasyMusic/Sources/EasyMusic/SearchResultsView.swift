import SwiftUI

struct SearchEntry: Identifiable {
    let track: Track?
    let collection: CatalogItem?
    var id: String { track.map { "track:" + $0.id } ?? collection!.id }
    var title: String { track?.title ?? collection!.name }
    var subtitle: String { track?.artist ?? collection!.subtitle }
    var artwork: String? { track?.artwork ?? collection?.artwork }
    var type: String {
        guard let kind = collection?.kind else { return "Titre" }
        return ["audiobook": "Livre audio", "album": "Album", "artist": "Artiste", "genre": "Style", "playlist": "Playlist"][kind] ?? "Sélection"
    }
    static func ranked(tracks: [Track], collections: [CatalogItem], query: String) -> [SearchEntry] {
        let values = tracks.map { SearchEntry(track: $0, collection: nil) } + collections.map { SearchEntry(track: nil, collection: $0) }
        func normalized(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines) }
        let q = normalized(query)
        func score(_ entry: SearchEntry) -> Int {
            let title = normalized(entry.title)
            return (title == q ? 100 : title.hasPrefix(q) ? 60 : title.contains(q) ? 40 : 0) + (normalized(entry.subtitle).contains(q) ? 10 : 0) + (entry.track?.isCatalog == true ? 2 : 0)
        }
        return values.sorted { score($0) == score($1) ? $0.id < $1.id : score($0) > score($1) }
    }
}
struct SearchResultsView: View {
    @EnvironmentObject var store: MusicStore
    var entries: [SearchEntry] {
        if store.openedCollection != nil { return store.visibleResults.map { SearchEntry(track: $0, collection: nil) } + store.catalogItems.map { SearchEntry(track: nil, collection: $0) } }
        return SearchEntry.ranked(tracks: store.visibleResults, collections: store.catalogItems, query: store.query)
    }
    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry, featured: index == 0 && store.openedCollection == nil)
            }
        }
    }
    private func row(_ entry: SearchEntry, featured: Bool) -> some View {
        HStack(spacing: 16) {
            if let track = entry.track { PlayableArtwork(track: track, size: featured ? 76 : 56) }
            Button {
                if let track = entry.track { store.select(track) }
                else if let collection = entry.collection { store.openCollection(collection) }
            } label: {
                HStack(spacing: 16) {
                    if entry.track == nil { Art(url: entry.artwork, size: featured ? 76 : 56)
                        .clipShape(RoundedRectangle(cornerRadius: entry.type == "Artiste" ? 38 : 4)) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.system(size: featured ? 23 : 14, weight: featured ? .bold : .medium)).lineLimit(1)
                        Text(entry.subtitle.isEmpty ? entry.type : entry.subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Text(entry.track != nil && store.openedCollection?.kind == "audiobook" ? "Chapitre" : entry.type).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 5).padding(.vertical, 3).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            if let track = entry.track {
                TrackPlaybackButtons(track: track, compact: true, showPlay: false)
                if store.downloaded(track) != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).help("Déjà téléchargé")
                } else {
                    Button { store.enqueue(track) } label: { Image(systemName: store.isQueued(track) ? "clock" : "arrow.down.circle").frame(width: 30, height: 36) }
                        .buttonStyle(.plain).disabled(store.isQueued(track)).help("Télécharger").accessibilityLabel("Télécharger \(track.title)")
                }
                PlaylistAddButton(track: track)
            } else {
                Image(systemName: "chevron.right").foregroundStyle(Theme.secondary).frame(width: 30)
            }
        }.padding(featured ? 16 : 10)
            .background(featured ? Color.white.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

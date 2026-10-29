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
        func normalized(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let q = normalized(query)
        guard !q.isEmpty else { return values }
        let queryWords = Matching.words(q)
        let variants: Set<String> = ["live", "remix", "cover", "karaoke", "acoustic", "acoustique", "instrumental", "sped", "slowed", "radio", "extended"]
        func containsPhrase(_ text: String, _ phrase: String) -> Bool {
            !phrase.isEmpty && (" " + text + " ").contains(" " + phrase + " ")
        }
        func score(_ entry: SearchEntry) -> Double {
            let title = normalized(Matching.titleForSearch(entry.title)), artist = normalized(entry.subtitle)
            let available = Matching.words(title + " " + artist)
            // A title followed by an artist is one query: both fields must contribute.
            var score = Double(queryWords.intersection(available).count) / Double(queryWords.count) * 1_000
            if title == q { score += 180 }
            else if containsPhrase(q, title) { score += 90 }
            else if containsPhrase(title, q) { score += 30 }
            // Complete credited names distinguish Renaud from Renaud Capuçon.
            if containsPhrase(q, artist) { score += 100 }
            if artist == q { score += 60 }
            let unrequestedVariants = Matching.words(title).intersection(variants).subtracting(queryWords)
            score -= Double(unrequestedVariants.count) * 80
            return score + (entry.track?.isCatalog == true ? 2 : 0)
        }
        // Keep provider relevance for indistinguishable names instead of ordering by database ID.
        let scored: [(entry: SearchEntry, offset: Int, relevance: Double)] = values.enumerated().map {
            (entry: $0.element, offset: $0.offset, relevance: score($0.element))
        }
        let sorted = scored.sorted { first, second in
            if first.relevance == second.relevance { return first.offset < second.offset }
            return first.relevance > second.relevance
        }
        return sorted.map { $0.entry }
    }
}
struct SearchResultsView: View {
    @EnvironmentObject var store: MusicStore
    var tracks: [Track]? = nil
    var entries: [SearchEntry] {
        if let tracks { return tracks.map { SearchEntry(track: $0, collection: nil) } }
        if store.openedCollection != nil { return store.visibleResults.map { SearchEntry(track: $0, collection: nil) } + store.catalogItems.map { SearchEntry(track: nil, collection: $0) } }
        return SearchEntry.ranked(tracks: store.visibleResults, collections: store.catalogItems, query: store.query)
    }
    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry, featured: index == 0 && store.openedCollection == nil && tracks == nil)
            }
        }
    }
    private func row(_ entry: SearchEntry, featured: Bool) -> some View {
        HStack(spacing: 12) {
            if let track = entry.track { TrackPlayButton(track: track) }
            Button {
                if let track = entry.track { store.select(track) }
                else if let collection = entry.collection { store.openCollection(collection) }
            } label: {
                HStack(spacing: 16) {
                    Art(url: entry.artwork, size: featured ? 76 : 56)
                        .clipShape(RoundedRectangle(cornerRadius: entry.type == "Artiste" ? 38 : 4))
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
                LikeButton(track: track)
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

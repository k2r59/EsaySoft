import SwiftUI

extension MusicStore {
    func preference(for track: Track) -> TrackPreference? {
        library.trackPreferences?.first { matchesRecording($0.track, track) }
    }
    func isLiked(_ track: Track) -> Bool { preference(for: track)?.liked == true }
    func rating(for track: Track) -> Int { preference(for: track)?.rating ?? 0 }
    var likedTracks: [Track] { (library.trackPreferences ?? []).filter(\.liked).map(\.track) }
    func setLiked(_ liked: Bool, for track: Track) {
        updatePreference(track) { $0.liked = liked }
    }
    func setRating(_ rating: Int, for track: Track) {
        updatePreference(track) { $0.rating = rating <= 0 ? nil : min(5, rating) }
    }
    private func updatePreference(_ track: Track, update: (inout TrackPreference) -> Void) {
        var rows = library.trackPreferences ?? []
        if let index = rows.firstIndex(where: { matchesRecording($0.track, track) }) { update(&rows[index]) }
        else { var entry = TrackPreference(track: track); update(&entry); rows.insert(entry, at: 0) }
        rows.removeAll { !$0.liked && $0.rating == nil }
        library.trackPreferences = rows
        save()
    }
}

struct LikeButton: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    var body: some View {
        Button { store.setLiked(!store.isLiked(track), for: track) } label: {
            Image(systemName: store.isLiked(track) ? "heart.fill" : "heart")
                .font(.system(size: 17)).foregroundStyle(store.isLiked(track) ? Theme.green : Theme.secondary)
                .frame(width: 32, height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help(store.isLiked(track) ? "Retirer des titres aimés" : "J’aime")
            .accessibilityLabel("J’aime · \(track.title)").accessibilityValue(store.isLiked(track) ? "Oui" : "Non")
    }
}

struct TrackRating: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button { store.setRating(store.rating(for: track) == value ? 0 : value, for: track) } label: {
                    Image(systemName: store.rating(for: track) >= value ? "star.fill" : "star")
                        .font(.system(size: 18)).foregroundStyle(store.rating(for: track) >= value ? Theme.green : Theme.secondary)
                        .frame(width: 36, height: 38)
                }.buttonStyle(.plain).help("\(value) sur 5 · recliquer pour effacer")
                    .accessibilityLabel("Noter \(value) sur 5").accessibilityValue(store.rating(for: track) >= value ? "Sélectionné" : "Non sélectionné")
            }
            Spacer(minLength: 0)
            if store.rating(for: track) > 0 { Text("\(store.rating(for: track))/5").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
        }.accessibilityElement(children: .contain).accessibilityLabel("Votre note")
    }
}

struct LikedTracksView: View {
    @EnvironmentObject var store: MusicStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    Image(systemName: "heart.fill").font(.system(size: 38)).foregroundStyle(.white)
                        .frame(width: 100, height: 100)
                        .background(LinearGradient(colors: [Color(red: 0.26, green: 0.13, blue: 0.68), Color(red: 0.54, green: 0.76, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Titres aimés").font(.system(size: 32, weight: .bold))
                        Text("\(store.likedTracks.count) \(store.likedTracks.count == 1 ? "titre" : "titres")").foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if let first = store.likedTracks.first { TrackPlayButton(track: first) }
                }
                if store.likedTracks.isEmpty {
                    Text("Touchez le cœur d’un titre pour le retrouver ici.").foregroundStyle(Theme.secondary).padding(.vertical, 40)
                } else { SearchResultsView(tracks: store.likedTracks) }
            }.padding(24)
        }
    }
}

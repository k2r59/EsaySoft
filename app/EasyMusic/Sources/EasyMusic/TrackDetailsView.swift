import SwiftUI

struct TrackDetailsView: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    @State private var artists: [CatalogItem] = []
    @State private var albums: [CatalogItem] = []
    @State private var loading = false
    @State private var djInfo: DJInfo?
    @State private var djLoading = false
    @State private var djUnavailable = false
    @State private var analyzeTrackID: String?
    @State private var analysisAttempt = 0
    private var djTaskID: String { track.id + "|" + (store.downloaded(track)?.path ?? "") + "|" + String(analyzeTrackID == track.id ? analysisAttempt : 0) }
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
                    LikeButton(track: track)
                    PlaylistAddButton(track: track)
                }
                TrackRating(track: track)
                djDetails
                TrackPlaybackButtons(track: track, showPlay: false)
                if let local = store.downloaded(track) {
                    Label("En local · \(local.bitrateLabel)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.system(size: 13))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Qualité audio").fontWeight(.semibold); if store.inspecting { ProgressView().controlSize(.small) } }
                        MusicSelect(title: "Qualité audio", selection: $store.selectedFormat,
                                    options: [SelectOption(id: "best", title: "Meilleure disponible")] + store.formats.map { SelectOption(id: $0.id, title: $0.label) })
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
                let related = try? await Catalog.relations(for: track)
                guard !Task.isCancelled else { return }
                artists = related.map { [$0.artist] } ?? []
                albums = related?.albums ?? []
            }
            .task(id: djTaskID) {
                djInfo = nil; djLoading = true; djUnavailable = false
                do {
                    let result = try await DJMetadata.shared.info(for: track, localPath: store.downloaded(track)?.path,
                                                                analyzeRemote: analyzeTrackID == track.id)
                    guard !Task.isCancelled else { return }
                    djInfo = result; djLoading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    djLoading = false; djUnavailable = true
                }
            }
    }
    private var djDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DJ").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondary)
                Spacer()
                if djLoading { ProgressView().controlSize(.mini).help("Analyse audio") }
            }
            HStack(alignment: .top, spacing: 10) {
                metric("BPM", value: djInfo?.bpm.map { (djInfo?.bpmSource?.hasPrefix("Estimation") == true ? "≈ " : "") + $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—",
                       detail: djInfo?.bpmSource ?? "")
                metric("Tonalité", value: djInfo?.key.map { (djInfo?.keySource?.hasPrefix("Estimation") == true ? "≈ " : "") + $0.camelot } ?? "—",
                       detail: djInfo?.key.map { $0.name + (djInfo?.keySource?.hasPrefix("Estimation") == true ? " · estimée" : "") } ?? "")
            }
            if !djLoading && (djInfo?.bpm == nil || djInfo?.key == nil) {
                Button {
                    analyzeTrackID = track.id; analysisAttempt += 1
                } label: { Label("Analyser l’audio", systemImage: "waveform.path") }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                    .help(djUnavailable ? "Analyse momentanément indisponible. Réessayer." : "Estimer les informations manquantes à partir de l’audio")
            }
        }.padding(14).background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
    private func metric(_ label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 23, weight: .bold)).monospacedDigit()
            if !detail.isEmpty { Text(detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
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

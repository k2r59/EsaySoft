import SwiftUI

struct TrackPlaybackButtons: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    var compact = false
    var showPlay = true
    var body: some View {
        HStack(spacing: 14) {
            if showPlay { Button {
                store.requestPlayback(track)
            } label: { Label(store.playing?.track.id == track.id && store.isPlaying ? "Pause" : "Lire", systemImage: store.playing?.track.id == track.id && store.isPlaying ? "pause.fill" : "play.fill") }
                .help("Lire le titre complet") }
            Button { store.preview(track) } label: {
                if store.previewLoadingID == track.id { ProgressView().controlSize(.small) }
                else { Label(store.previewing?.id == track.id && store.isPlaying ? "Arrêter" : "Extrait", systemImage: "waveform") }
            }.disabled(!store.canPreview(track) || store.previewLoadingID == track.id).help("Écouter un extrait de 30 secondes maximum")
        }.labelStyle(PlaybackLabelStyle(compact: compact)).buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).fixedSize()
    }
}

private struct PlaybackLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon; if !compact { configuration.title } }.frame(minWidth: 28, minHeight: 36)
    }
}

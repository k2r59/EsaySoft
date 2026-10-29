import SwiftUI

struct PlayableArtwork: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    var size: CGFloat = 56
    @State private var hovered = false
    var local: LocalTrack? { store.downloaded(track) }
    var playing: Bool { store.previewing == nil && store.currentTrack.map { store.matchesRecording($0, track) } == true && store.isPlaying }
    var body: some View {
        Button { store.requestPlayback(track) } label: {
            Art(url: track.artwork, size: size)
                .overlay {
                    Color.black.opacity(hovered || playing ? 0.32 : 0.12)
                    if store.requestedPlayback.map({ store.matchesRecording($0, track) }) == true { ProgressView().controlSize(.small).frame(width: size > 100 ? 48 : 30, height: size > 100 ? 48 : 30).background(Color.black.opacity(0.7), in: Circle()) }
                    else { Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: size > 100 ? 22 : 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: size > 100 ? 48 : 30, height: size > 100 ? 48 : 30)
                        .background(Theme.green, in: Circle()) }
                }.clipShape(RoundedRectangle(cornerRadius: size > 100 ? 8 : 4))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help(store.requestedPlayback?.id == track.id ? "Annuler la lecture" : playing ? "Mettre en pause" : "Lire le titre")
            .accessibilityLabel(playing ? "Mettre \(track.title) en pause" : "Lire \(track.title)")
    }
}

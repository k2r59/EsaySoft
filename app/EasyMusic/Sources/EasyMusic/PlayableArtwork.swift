import SwiftUI

struct PlayableArtwork: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    var size: CGFloat = 56
    @State private var hovered = false
    var local: LocalTrack? { store.downloaded(track) }
    var playing: Bool { local != nil && store.playing?.id == local?.id && store.isPlaying }
    var body: some View {
        Button {
            guard let local else { return }
            if store.playing?.id == local.id { store.togglePlayback() } else { store.play(local) }
        } label: {
            Art(url: track.artwork, size: size)
                .overlay {
                    Color.black.opacity(hovered || playing ? 0.32 : 0.12)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: size > 100 ? 22 : 14, weight: .bold))
                        .foregroundStyle(local == nil ? Color.white.opacity(0.6) : .black)
                        .frame(width: size > 100 ? 48 : 30, height: size > 100 ? 48 : 30)
                        .background(local == nil ? Color.black.opacity(0.45) : Theme.green, in: Circle())
                }.clipShape(RoundedRectangle(cornerRadius: size > 100 ? 8 : 4))
        }.buttonStyle(.plain).disabled(local == nil).onHover { hovered = $0 }
            .help(local == nil ? "Téléchargez le titre pour le lire en entier" : playing ? "Mettre en pause" : "Lire le titre")
            .accessibilityLabel(playing ? "Mettre \(track.title) en pause" : "Lire \(track.title)")
    }
}

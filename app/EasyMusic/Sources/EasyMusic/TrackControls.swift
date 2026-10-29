import SwiftUI

struct TrackPlayButton: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    private var waiting: Bool { store.requestedPlayback.map { store.matchesRecording($0, track) } == true }
    private var playing: Bool { store.previewing == nil && store.currentTrack.map { store.matchesRecording($0, track) } == true && store.isPlaying }
    private var action: String { waiting ? "Annuler la lecture" : playing ? "Mettre en pause" : "Lire" }
    var body: some View {
        Button { store.requestPlayback(track) } label: {
            ZStack {
                Circle().fill(Theme.green).frame(width: 32, height: 32)
                if waiting { ProgressView().controlSize(.small).tint(.black) }
                else { Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.black) }
            }.frame(width: 40, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).help(action).accessibilityLabel("\(action) · \(track.title)")
    }
}

struct TrackArtworkButton: View {
    @EnvironmentObject var store: MusicStore
    let track: Track
    var size: CGFloat = 56
    var body: some View {
        Button { store.select(track) } label: { Art(url: track.artwork, size: size) }
            .buttonStyle(.plain).help("Afficher les détails").accessibilityLabel("Détails de \(track.title)")
    }
}

struct SelectOption: Identifiable {
    let id: String
    let title: String
}

struct MusicSelect: View {
    let title: String
    @Binding var selection: String
    let options: [SelectOption]
    @State private var hovered = false
    @State private var expanded = false
    var selectedTitle: String { options.first { $0.id == selection }?.title ?? options.first?.title ?? "—" }
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 12) {
                Text(selectedTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            }.foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 42)
                .background(hovered ? Color(white: 0.19) : Theme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(hovered ? 0.28 : 0.14), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .onHover { hovered = $0 }.accessibilityLabel(title).accessibilityValue(selectedTitle).help(selectedTitle)
            .popover(isPresented: $expanded, arrowEdge: .top) {
                VStack(spacing: 4) {
                    ForEach(options) { option in
                        Button {
                            selection = option.id
                            expanded = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(option.title).font(.system(size: 13, weight: .medium))
                                Spacer(minLength: 8)
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.green).opacity(selection == option.id ? 1 : 0)
                            }.foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 40)
                                .background(selection == option.id ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(option.title)
                            .accessibilityValue(selection == option.id ? "Sélectionné" : "")
                    }
                }.padding(8).frame(width: 260).background(Theme.card)
                    .onExitCommand { expanded = false }
            }
    }
}

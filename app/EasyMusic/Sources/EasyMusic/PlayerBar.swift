import SwiftUI
import AppKit
import AVKit

struct SpotifyPlayerBar: View {
    @EnvironmentObject var store: MusicStore
    @State private var showQueue = false
    @State private var expanded = false
    @State private var seeking = false
    @State private var seekPosition = 0.0
    var track: Track? { store.requestedPlayback ?? store.currentTrack }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button { expanded.toggle() } label: { Art(url: track?.artwork, size: 56) }.buttonStyle(.plain).disabled(track == nil).help("Afficher le morceau")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track?.title ?? "Aucun titre en lecture").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(store.requestedPlayback != nil ? "Connexion…" : store.isBuffering ? "Chargement…" : track?.artist ?? "").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    if let track {
                        Button { if store.downloaded(track) == nil { store.enqueue(track) } else { store.section = "library" } } label: {
                            Image(systemName: store.downloaded(track) == nil ? "arrow.down.circle" : "checkmark.circle.fill")
                                .foregroundStyle(store.downloaded(track) == nil ? Theme.secondary : Theme.green)
                        }.buttonStyle(.plain).help(store.downloaded(track) == nil ? "Télécharger" : "Dans la bibliothèque")
                    }
                    Spacer(minLength: 0)
                }.frame(width: geometry.size.width * 0.27)
                VStack(spacing: 8) {
                    HStack(spacing: 24) {
                        control("shuffle", label: "Lecture aléatoire", active: store.shuffle, disabled: !store.hasFullPlayback) { store.toggleShuffle() }
                        control("backward.end.fill", label: "Précédent", disabled: !store.hasFullPlayback) { store.next(-1) }
                        Button { store.togglePlayback() } label: {
                            if store.requestedPlayback != nil { ProgressView().controlSize(.small).frame(width: 32, height: 32) }
                            else { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.black).frame(width: 32, height: 32).background(.white, in: Circle()) }
                        }.buttonStyle(.plain).disabled(store.player.currentItem == nil && store.requestedPlayback == nil).accessibilityLabel(store.requestedPlayback != nil ? "Annuler la lecture" : store.isPlaying ? "Pause" : "Lire")
                        control("forward.end.fill", label: "Suivant", disabled: !store.hasFullPlayback) { store.next() }
                        control(store.repeatMode == 2 ? "repeat.1" : "repeat", label: ["Répétition désactivée", "Répéter la file", "Répéter ce titre"][store.repeatMode], active: store.repeatMode != 0, disabled: !store.hasFullPlayback) { store.repeatMode = (store.repeatMode + 1) % 3 }
                    }
                    HStack(spacing: 8) {
                        Text(time(seeking ? seekPosition : store.position)).frame(width: 32, alignment: .trailing)
                        Slider(value: Binding(get: { seeking ? seekPosition : min(store.position, max(1, store.playerDuration)) }, set: { seekPosition = $0 }), in: 0...max(1, store.playerDuration), onEditingChanged: { editing in
                            if editing { seekPosition = store.position; seeking = true }
                            else { store.seek(seekPosition); seeking = false }
                        }).controlSize(.mini).tint(.white).disabled(store.playerDuration <= 0 || store.requestedPlayback != nil).accessibilityLabel("Position de lecture")
                        Text(time(store.playerDuration)).frame(width: 32, alignment: .leading)
                    }.font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity)
                HStack(spacing: 14) {
                    Button { showQueue.toggle() } label: { Image(systemName: "list.bullet").foregroundStyle(showQueue ? Theme.green : Theme.secondary) }.buttonStyle(.plain).help("File d’attente")
                        .popover(isPresented: $showQueue) { queue.padding(18).frame(width: 340, height: 350) }
                    AudioOutputPicker().frame(width: 22, height: 24).help("Sortie audio")
                    Button { store.toggleMute() } label: { Image(systemName: store.volume == 0 ? "speaker.slash" : "speaker.wave.2").foregroundStyle(Theme.secondary) }.buttonStyle(.plain).help("Couper ou rétablir le son")
                    Slider(value: $store.volume, in: 0...1).controlSize(.mini).tint(.white).frame(width: 78).accessibilityLabel("Volume")
                    control("arrow.up.left.and.arrow.down.right", label: "Plein écran") { NSApp.keyWindow?.toggleFullScreen(nil) }
                }.frame(width: geometry.size.width * 0.25, alignment: .trailing)
            }.padding(.horizontal, 16).frame(height: geometry.size.height)
        }.background(.black)
        .sheet(isPresented: $expanded) {
            VStack(spacing: 20) {
                Art(url: track?.artwork, size: 300)
                Text(track?.title ?? "").font(.title2.bold()).multilineTextAlignment(.center)
                Text(store.requestedPlayback != nil ? "Connexion…" : store.isBuffering ? "Chargement…" : track?.artist ?? "").foregroundStyle(Theme.secondary)
                Button(store.requestedPlayback != nil ? "Annuler" : store.isPlaying ? "Pause" : "Lire") { store.togglePlayback() }.buttonStyle(GreenButton())
                Button("Fermer") { expanded = false }.keyboardShortcut(.cancelAction)
            }.padding(30).frame(width: 380)
        }
    }
    func control(_ icon: String, label: String, active: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14)).frame(height: 17)
                Circle().fill(active ? Theme.green : .clear).frame(width: 3, height: 3)
            }.foregroundStyle(active ? Theme.green : Theme.secondary)
        }.buttonStyle(.plain).disabled(disabled).help(label).accessibilityLabel(label)
    }
    var queue: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("File d’attente").font(.headline)
                ForEach(store.activeDownloads) { active in
                    Text(active.track.title).lineLimit(1); ProgressView(value: active.progress)
                    Text(active.phase).font(.caption).foregroundStyle(Theme.secondary)
                }
                ForEach(store.pending) { track in Label(track.title, systemImage: "arrow.down").lineLimit(1) }
                Divider()
                ForEach(store.playbackQueue) { song in
                    Button { store.requestPlayback(song, keepQueue: true) } label: {
                        HStack { Art(url: song.artwork, size: 32); Text(song.title).lineLimit(1); Spacer() }
                            .foregroundStyle(store.currentTrack?.id == song.id ? Theme.green : .white)
                    }.buttonStyle(.plain)
                }
                if store.pending.isEmpty && store.activeTitle == nil && store.playbackQueue.isEmpty { Text("La file est vide.").foregroundStyle(Theme.secondary) }
            }
        }
    }
    func time(_ value: Double) -> String { guard value.isFinite, value >= 0 else { return "0:00" }; return String(format: "%d:%02d", Int(value)/60, Int(value)%60) }
}
struct AudioOutputPicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(NSColor(white: 0.70, alpha: 1), for: .normal)
        view.setRoutePickerButtonColor(NSColor.white, for: .normalHighlighted)
        view.setRoutePickerButtonColor(NSColor(red: 0.12, green: 0.85, blue: 0.39, alpha: 1), for: .active)
        return view
    }
    func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}

import SwiftUI

struct RenamePlaylistSheet: View {
    @EnvironmentObject var store: MusicStore
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var name: String
    @FocusState private var focused: Bool

    init(playlist: Playlist) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Renommer la playlist").font(.system(size: 23, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary).frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.07), in: Circle())
                }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Annuler le renommage")
            }
            TextField("Nom de la playlist", text: $name).textFieldStyle(.plain).font(.system(size: 16))
                .padding(.horizontal, 16).frame(height: 54)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Theme.green : Color.white.opacity(0.15), lineWidth: 1))
                .focused($focused).onSubmit(save).accessibilityLabel("Nom de la playlist")
            HStack {
                Spacer()
                Button("Enregistrer", action: save).buttonStyle(GreenButton())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 460).background(Theme.surface).onAppear { focused = true }
    }
    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.renamePlaylist(playlist.id, to: name); dismiss()
    }
}

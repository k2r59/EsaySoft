import Foundation

extension MusicStore {
    func renamePlaylist(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        library.playlists[index].name = String(clean.prefix(160)); save()
    }
    func checkPlaylistUpdates(force: Bool = false,
        load: (String) async throws -> ImportedPlaylist = PlaylistImport.load) async {
        for playlist in library.playlists where playlist.sourceURL != nil {
            if !force, let last = playlist.lastSyncCheck, Date().timeIntervalSince(last) < 900 { continue }
            await refreshPlaylist(playlist.id, apply: false, load: load)
        }
    }
    func refreshPlaylist(_ id: UUID, apply: Bool,
        load: (String) async throws -> ImportedPlaylist = PlaylistImport.load) async {
        guard let original = library.playlists.first(where: { $0.id == id }), let url = original.sourceURL,
              !checkingPlaylists.contains(id) else { return }
        checkingPlaylists.insert(id); syncErrors[id] = nil
        defer { checkingPlaylists.remove(id) }
        do {
            let remote = try await load(url)
            guard let index = library.playlists.firstIndex(where: { $0.id == id && $0.sourceURL == url }) else { return }
            let current = library.playlists[index].importedTracks ?? []
            library.playlists[index].hasRemoteChanges = current.map(\.id) != remote.tracks.map(\.id)
            library.playlists[index].lastSyncCheck = Date()
            if apply {
                // Only the imported portion follows the source. The local name, additions and audio files survive.
                library.playlists[index].importedTracks = remote.tracks
                library.playlists[index].importWarning = remote.warning
                library.playlists[index].hasRemoteChanges = false
                notice = "Playlist synchronisée : \(remote.tracks.count) titres."
            }
            save()
        } catch {
            syncErrors[id] = "Synchronisation indisponible. La playlist locale est conservée. Réessayez plus tard."
            if let index = library.playlists.firstIndex(where: { $0.id == id }) {
                library.playlists[index].lastSyncCheck = Date(); save()
            }
            // A failed request must never erase a previously detected change or an imported list.
        }
    }
}

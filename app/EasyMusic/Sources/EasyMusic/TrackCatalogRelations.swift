import Foundation

struct TrackCatalogRelations {
    let artist: CatalogItem
    let albums: [CatalogItem]
}

extension Catalog {
    static func trackMetadata(_ id: Int) async throws -> [String: Any] {
        let data = try await Engine.request(URL(string: "https://api.deezer.com/track/\(id)")!)
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any], row["id"] as? Int == id else {
            throw MusicError.message("Les informations de ce titre sont indisponibles.")
        }
        return row
    }

    static func relations(for track: Track,
                          loadTrack: (Int) async throws -> [String: Any] = trackMetadata,
                          searchTracks: (String) async throws -> [[String: Any]] = {
                              try await rows("search", query: [URLQueryItem(name: "q", value: $0), URLQueryItem(name: "limit", value: "25")])
                          },
                          loadAlbums: (Int) async throws -> [[String: Any]] = {
                              try await rows("artist/\($0)/albums", query: [URLQueryItem(name: "limit", value: "4")])
                          }) async throws -> TrackCatalogRelations? {
        func key(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        func artist(_ row: [String: Any]) -> [String: Any]? {
            guard let value = row["artist"] as? [String: Any], let id = value["id"] as? Int, id > 0,
                  let name = value["name"] as? String, !name.isEmpty, key(name) == key(track.artist) else { return nil }
            return value
        }
        try Task.checkCancellation()
        let recording: [String: Any]
        if track.id.hasPrefix("deezer:"), let id = Int(track.id.dropFirst(7)), id > 0 {
            recording = try await loadTrack(id)
            guard recording["id"] as? Int == id, artist(recording) != nil else { return nil }
        } else {
            let title = key(Matching.titleForSearch(track.title))
            guard !title.isEmpty, !key(track.artist).isEmpty else { return nil }
            let candidates = try await searchTracks(Matching.titleForSearch(track.title) + " " + track.artist)
            let exact = candidates.filter {
                guard let candidateTitle = $0["title"] as? String else { return false }
                return key(Matching.titleForSearch(candidateTitle)) == title && artist($0) != nil
                    && AudioStreaming.durationMatches($0["duration"] as? Double, track.duration)
            }
            let artistIDs = Set(exact.compactMap { artist($0)?["id"] as? Int })
            guard artistIDs.count == 1, let first = exact.first else { return nil }
            recording = first
        }
        try Task.checkCancellation()
        guard let identity = artist(recording), let artistItem = items([identity], kind: "artist").first else { return nil }
        var albumRows = [[String: Any]]()
        if let originalAlbum = recording["album"] as? [String: Any] { albumRows.append(originalAlbum) }
        do { albumRows += try await loadAlbums(artistItem.key) }
        catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation() }
        try Task.checkCancellation()
        var seen = Set<String>()
        let verifiedRows = albumRows.filter { row in
            guard let albumArtist = row["artist"] as? [String: Any], let id = albumArtist["id"] as? Int else { return true }
            return id == artistItem.key
        }
        let albums = items(verifiedRows, kind: "album").filter { seen.insert($0.id).inserted }
        return TrackCatalogRelations(artist: artistItem, albums: Array(albums.prefix(4)))
    }
}

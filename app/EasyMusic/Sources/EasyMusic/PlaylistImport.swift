import Foundation

struct ImportedPlaylist {
    var name: String
    var sourceURL: String
    var tracks: [Track]
    var warning: String?
}

enum PlaylistImport {
    enum Source: Equatable { case spotify(String), deezer(Int), youtube(String) }
    static func source(_ text: String) throws -> Source {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
              let host = url.host?.lowercased() else { throw invalidLink }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "open.spotify.com", let index = parts.firstIndex(of: "playlist"), index + 2 == parts.count {
            let key = parts[index + 1]
            guard key.count == 22, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw invalidLink }
            return .spotify(key)
        }
        if ["deezer.com", "www.deezer.com"].contains(host), let index = parts.firstIndex(of: "playlist"), index + 2 == parts.count,
           let key = Int(parts[index + 1]), key > 0 { return .deezer(key) }
        if ["youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com", "youtu.be"].contains(host),
           let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "list" })?.value,
           (10...100).contains(key.count), key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) {
            guard !key.hasPrefix("RD"), key != "WL", key != "LL" else {
                throw MusicError.message("Les radios automatiques et listes privées YouTube ne sont pas importables. Utilisez une playlist partagée.")
            }
            return .youtube(key)
        }
        throw invalidLink
    }
    static var invalidLink: MusicError { .message("Collez le lien complet d’une playlist Spotify, Deezer ou YouTube Music accessible sans connexion.") }
    static func load(_ text: String) async throws -> ImportedPlaylist {
        switch try source(text) {
        case .deezer(let key):
            let data = try await Engine.request(URL(string: "https://api.deezer.com/playlist/\(key)")!)
            guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = Catalog.items([row], kind: "playlist").first, row["error"] == nil else {
                throw MusicError.message("Cette playlist Deezer est privée ou indisponible.")
            }
            let tracks = try await Catalog.tracks(in: item)
            let total = row["nb_tracks"] as? Int
            return try checked(ImportedPlaylist(name: item.name, sourceURL: "https://www.deezer.com/playlist/\(key)", tracks: tracks,
                warning: total.map { $0 > tracks.count ? "\(tracks.count) titres récupérés sur \($0). Certains titres sont indisponibles ou répétés." : nil } ?? nil))
        case .spotify(let key):
            let data = try await Engine.request(URL(string: "https://open.spotify.com/embed/playlist/\(key)")!)
            return try spotify(data, key: key)
        case .youtube(let key):
            let url = "https://music.youtube.com/playlist?list=\(key)"
            let output = try await Engine.run(["--yes-playlist", "--flat-playlist", "--skip-download", "--ignore-errors", "--playlist-end", "2001", "--dump-single-json", "--", url], timeout: 180)
            guard let row = Engine.jsonLines(output).last else { throw MusicError.message("Cette playlist YouTube Music est privée ou indisponible.") }
            return try youtube(row, url: url)
        }
    }
    static func spotify(_ data: Data, key: String) throws -> ImportedPlaylist {
        let html = String(decoding: data, as: UTF8.self)
        let regex = try NSRegularExpression(pattern: "<script[^>]*id=[\"']__NEXT_DATA__[\"'][^>]*>(.*?)</script>", options: [.dotMatchesLineSeparators])
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let root = try JSONSerialization.jsonObject(with: Data(html[range].utf8)) as? [String: Any],
              let props = root["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let state = page["state"] as? [String: Any], let content = state["data"] as? [String: Any],
              let entity = content["entity"] as? [String: Any], let rows = entity["trackList"] as? [[String: Any]] else {
            throw MusicError.message("Spotify ne rend pas cette playlist accessible sans connexion. Vérifiez qu’elle est publique ou réessayez plus tard.")
        }
        let cover = ((entity["coverArt"] as? [String: Any])?["sources"] as? [[String: Any]])?.first?["url"] as? String
        let tracks = rows.compactMap { row -> Track? in
            guard let uri = row["uri"] as? String, uri.hasPrefix("spotify:track:"),
                  let title = row["title"] as? String, !title.isEmpty else { return nil }
            let id = String(uri.dropFirst("spotify:track:".count))
            guard id.count == 22, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
            let artists = (row["subtitle"] as? String ?? "").components(separatedBy: ",\u{00a0}")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return Track(id: "spotify:\(id)", title: title, artist: row["subtitle"] as? String ?? "",
                         duration: (row["duration"] as? Double).map { $0 / 1000 }, artwork: cover,
                         url: "https://open.spotify.com/track/\(id)", source: "Spotify",
                         preview: (row["audioPreview"] as? [String: Any])?["url"] as? String, isCatalog: true, artistCredits: artists)
        }
        return try checked(ImportedPlaylist(name: entity["name"] as? String ?? "Playlist Spotify",
            sourceURL: "https://open.spotify.com/playlist/\(key)", tracks: tracks,
            warning: "Import depuis la page publique Spotify : seuls les titres exposés sont récupérés. La liste complète n’est pas garantie."))
    }
    static func youtube(_ row: [String: Any], url: String) throws -> ImportedPlaylist {
        guard let entries = row["entries"] as? [Any] else { throw invalidLink }
        guard entries.count <= 2000 else { throw MusicError.message("Cette playlist dépasse la limite de 2 000 titres. Importez une sélection plus petite.") }
        let tracks = entries.compactMap { entry -> Track? in
            guard let item = entry as? [String: Any], let id = item["id"] as? String, id.count == 11,
                  id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
                  let title = item["title"] as? String, !["[Private video]", "[Deleted video]"].contains(title),
                  !["private", "premium_only", "subscriber_only"].contains(item["availability"] as? String ?? "") else { return nil }
            return Track(id: "YouTube:\(id)", title: title, artist: item["artist"] as? String ?? item["uploader"] as? String ?? "",
                         duration: item["duration"] as? Double,
                         artwork: (item["thumbnails"] as? [[String: Any]])?.last?["url"] as? String,
                         url: "https://www.youtube.com/watch?v=\(id)", source: "YouTube")
        }
        let total = row["playlist_count"] as? Int ?? entries.count
        return try checked(ImportedPlaylist(name: row["title"] as? String ?? "Playlist YouTube Music", sourceURL: url,
            tracks: tracks, warning: tracks.count < total ? "\(tracks.count) titres récupérés sur \(total). Certains titres sont privés ou indisponibles." : nil))
    }
    static func checked(_ playlist: ImportedPlaylist) throws -> ImportedPlaylist {
        guard !playlist.tracks.isEmpty else { throw MusicError.message("Aucun titre accessible dans cette playlist. Aucun import n’a été créé.") }
        var result = playlist, seen = Set<String>()
        result.tracks = playlist.tracks.filter { seen.insert($0.id).inserted }
        return result
    }
}

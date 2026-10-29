import Foundation

enum SearchMode: String, CaseIterable, Identifiable {
    case all = "Tout", genres = "Styles", tracks = "Titres", albums = "Albums", artists = "Artistes", playlists = "Playlists"
    var id: String { rawValue }
    var placeholder: String {
        switch self {
        case .all, .tracks: return "Un titre, un artiste ou un lien"
        case .playlists: return "Nom d’une playlist"
        case .albums: return "Nom d’un album"
        case .artists: return "Nom d’un artiste"
        case .genres: return "Jazz, rock, électro…"
        }
    }
}
struct CatalogItem: Identifiable, Hashable, Codable {
    let key: Int
    let name: String
    let subtitle: String
    let artwork: String?
    let kind: String
    var id: String { "\(kind):\(key)" }
}
enum Catalog {
    static func rows(_ path: String, query: [URLQueryItem] = []) async throws -> [[String: Any]] {
        var url = URLComponents(string: "https://api.deezer.com/" + path)!
        url.queryItems = query.isEmpty ? nil : query
        let data = try await Engine.request(url.url!)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = obj["data"] as? [[String: Any]] else {
            throw MusicError.message("Le catalogue est indisponible. Réessayez dans un instant.")
        }
        return rows
    }
    static func items(_ rows: [[String: Any]], kind: String) -> [CatalogItem] {
        rows.compactMap { row in
            guard let id = row["id"] as? Int, let name = (row["title"] ?? row["name"]) as? String else { return nil }
            let artist = (row["artist"] ?? row["user"]) as? [String: Any]
            return CatalogItem(key: id, name: name, subtitle: artist?["name"] as? String ?? "",
                               artwork: (row["cover_big"] ?? row["picture_big"]) as? String, kind: kind)
        }
    }
    static func search(_ term: String, mode: SearchMode) async throws -> [CatalogItem] {
        if mode == .genres {
            let genres = items(try await rows("genre"), kind: "genre").filter { $0.key != 0 }
            let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return genres }
            let normalized = normalizeGenre(value)
            return genres.filter { normalizeGenre($0.name).contains(normalized) || normalized.contains(normalizeGenre($0.name)) }
        }
        let kind = mode == .albums ? "album" : mode == .playlists ? "playlist" : "artist"
        let results = try await rows("search/" + kind, query: [URLQueryItem(name: "q", value: term), URLQueryItem(name: "limit", value: "24")])
        return items(kind == "artist" ? rankArtistHomonyms(results) : results, kind: kind)
    }
    static func rankArtistHomonyms(_ rows: [[String: Any]]) -> [[String: Any]] {
        func name(_ row: [String: Any]) -> String {
            (row["name"] as? String ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result = rows
        let groups = Dictionary(grouping: rows.indices, by: { name(rows[$0]) })
        for (name, positions) in groups where !name.isEmpty && positions.count > 1 {
            // Missing fan counts are not popularity evidence: leave that group untouched.
            guard positions.allSatisfy({ rows[$0]["nb_fan"] as? Int != nil }) else { continue }
            let ranked = positions.sorted {
                let first = rows[$0]["nb_fan"] as! Int, second = rows[$1]["nb_fan"] as! Int
                return first == second ? $0 < $1 : first > second
            }
            for (position, source) in zip(positions, ranked) { result[position] = rows[source] }
        }
        return result
    }
    static func normalizeGenre(_ raw: String) -> String {
        let normalized = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let aliases = ["electro": "electro", "electronic": "electro", "electronique": "electro", "hip hop": "rap/hip hop", "hip-hop": "rap/hip hop", "rnb": "r&b", "classical": "classique", "livre audio": "livres audio", "audiobook": "livres audio", "audiobooks": "livres audio"]
        return aliases[normalized] ?? normalized
    }
    static func albumGenreIDs(_ row: [String: Any]) -> Set<Int> {
        var ids = Set<Int>()
        if let primary = row["genre_id"] as? Int, primary > 0 { ids.insert(primary) }
        if let genres = row["genres"] as? [String: Any], let data = genres["data"] as? [[String: Any]] {
            ids.formUnion(data.compactMap { $0["id"] as? Int }.filter { $0 > 0 })
        }
        return ids
    }
    static func album(_ id: Int) async throws -> [String: Any] {
        let data = try await Engine.request(URL(string: "https://api.deezer.com/album/\(id)")!)
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any], row["id"] as? Int == id else {
            throw MusicError.message("Cet album n’est pas disponible dans le catalogue.")
        }
        return row
    }
    /// Some genre/artists responses silently return the general chart. Verify each album's own metadata instead.
    static func albums(in genre: CatalogItem, limit: Int = 24,
                       loadRows: (String, [URLQueryItem]) async throws -> [[String: Any]] = { try await rows($0, query: $1) },
                       loadAlbum: @escaping (Int) async throws -> [String: Any] = album) async throws -> [CatalogItem] {
        guard genre.kind == "genre", genre.key > 0 else { return [] }
        let candidates = try await loadRows("chart/\(genre.key)/albums", [URLQueryItem(name: "limit", value: String(limit))])
        let verified = await verifiedAlbums(candidates, genreID: genre.key, loadAlbum: loadAlbum)
        return items(verified, kind: genre.key == 457 ? "audiobook" : "album")
    }
    static func verifiedAlbums(_ candidates: [[String: Any]], genreID: Int,
                               loadAlbum: @escaping (Int) async throws -> [String: Any] = album) async -> [[String: Any]] {
        var seen = Set<Int>(), verified: [[String: Any]] = []
        let unique = candidates.filter { row in guard let id = row["id"] as? Int else { return false }; return seen.insert(id).inserted }
        for start in stride(from: 0, to: unique.count, by: 4) {
            let chunk = Array(unique[start..<min(start + 4, unique.count)])
            let results = await withTaskGroup(of: (Int, [String: Any]?).self) { group in
                for (index, row) in chunk.enumerated() {
                    group.addTask {
                        let value = try? await loadAlbum(row["id"] as! Int)
                        guard let value, albumGenreIDs(value).contains(genreID) else { return (index, nil) }
                        return (index, value)
                    }
                }
                var result: [(Int, [String: Any]?)] = []
                for await value in group { result.append(value) }
                return result.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
            }
            verified += results
        }
        return verified
    }
    static func artists(in genre: CatalogItem) async throws -> [CatalogItem] {
        let candidates = try await rows("chart/\(genre.key)/albums", query: [URLQueryItem(name: "limit", value: "24")])
        let verified = await verifiedAlbums(candidates, genreID: genre.key)
        var seen = Set<String>()
        return items(verified.compactMap { $0["artist"] as? [String: Any] }, kind: "artist").filter { seen.insert($0.id).inserted }
    }
    static func tracks(_ rows: [[String: Any]], artwork: String? = nil) -> [Track] {
        rows.compactMap { row in
            guard let id = row["id"] as? Int, let title = row["title"] as? String else { return nil }
            let artist = (row["artist"] ?? row["user"]) as? [String: Any], album = row["album"] as? [String: Any]
            return Track(id: "deezer:\(id)", title: title, artist: artist?["name"] as? String ?? "",
                         duration: row["duration"] as? Double, artwork: album?["cover_big"] as? String ?? artwork,
                         url: row["link"] as? String ?? "https://www.deezer.com/track/\(id)", source: "Deezer",
                         preview: row["preview"] as? String, isCatalog: true)
        }
    }
    static func charts(genre: Int = 0) async throws -> [Track] {
        tracks(try await rows("chart/\(genre)/tracks", query: [URLQueryItem(name: "limit", value: "12")]))
    }
    static func playlists(_ query: String, limit: Int = 2) async throws -> [CatalogItem] {
        items(try await rows("search/playlist", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]), kind: "playlist")
    }
    static func homeMixes(queries: [String] = Recommendations.generalQueries, limit: Int = 1) async -> [CatalogItem] {
        await withTaskGroup(of: (Int, [CatalogItem]).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask { (index, await relatedCollections(query, limit: limit)) }
            }
            var sections: [(Int, [CatalogItem])] = []
            for await result in group { sections.append(result) }
            var ids = Set<String>()
            return sections.sorted { $0.0 < $1.0 }.flatMap { $0.1 }.filter { ids.insert($0.id).inserted }
        }
    }
    static func relatedCollections(_ query: String, limit: Int = 2) async -> [CatalogItem] {
        let candidates = ((try? await playlists(query, limit: 12)) ?? []).filter { Recommendations.titleMatches($0.name, query: query) }
        var accepted: [CatalogItem] = []
        for candidate in candidates.prefix(4) {
            guard accepted.count < limit, !Task.isCancelled else { break }
            if await playlistMatches(candidate, query: query) { accepted.append(candidate) }
        }
        if accepted.isEmpty, Recommendations.genreID(query) == nil {
            let artists = (try? await search(query, mode: .artists)) ?? []
            if let exact = artists.first(where: { Recommendations.contentKey($0.name) == Recommendations.contentKey(query) }),
               let rows = try? await rows("artist/\(exact.key)/albums", query: [URLQueryItem(name: "limit", value: String(limit))]) {
                return items(rows, kind: "album")
            }
        }
        return accepted
    }
    static func playlistMatches(_ item: CatalogItem, query: String) async -> Bool {
        guard let tracks = try? await rows("playlist/\(item.key)/tracks", query: [URLQueryItem(name: "limit", value: "12")]), !tracks.isEmpty else { return false }
        if let genre = Recommendations.genreID(query) {
            var seen = Set<Int>()
            let samples = tracks.compactMap { $0["album"] as? [String: Any] }.filter { row in
                guard let id = row["id"] as? Int else { return false }; return seen.insert(id).inserted
            }
            let examined = Array(samples.prefix(5))
            guard examined.count >= min(3, tracks.count) else { return false }
            let verified = await verifiedAlbums(examined, genreID: genre)
            return verified.count >= Int(ceil(Double(examined.count) * 0.6))
        }
        return Recommendations.contentMatches(tracks, query: query)
    }
    static func direct(_ url: URL) async throws -> (String, [Track]) {
        let parts = url.pathComponents
        guard url.scheme == "https", let raw = parts.last, let key = Int(raw), parts.count >= 3,
              ["track", "album", "artist"].contains(parts[parts.count - 2]) else {
            throw MusicError.message("Collez un lien Deezer vers un titre, un album ou un artiste.")
        }
        let kind = parts[parts.count - 2]
        let data = try await Engine.request(URL(string: "https://api.deezer.com/\(kind)/\(key)")!)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], obj["error"] == nil else {
            throw MusicError.message("Ce lien Deezer est introuvable.")
        }
        if kind == "track" { return (obj["title"] as? String ?? "Titre", tracks([obj])) }
        guard let item = items([obj], kind: kind).first else { throw MusicError.message("Ce lien Deezer n’a pas pu être lu.") }
        return (item.name, try await tracks(in: item))
    }
    static func tracks(in item: CatalogItem) async throws -> [Track] {
        let kind = item.kind == "audiobook" ? "album" : item.kind
        let path = kind == "artist" ? "artist/\(item.key)/top" : "\(kind)/\(item.key)/tracks"
        var next: URL? = URL(string: "https://api.deezer.com/\(path)?limit=100")
        var allRows: [[String: Any]] = []
        var visited = Set<String>()
        while let page = next {
            guard page.scheme == "https", page.host == "api.deezer.com", visited.insert(page.absoluteString).inserted,
                  visited.count <= 50 else { throw MusicError.message("Cette sélection ne peut pas être chargée complètement.") }
            let data = try await Engine.request(page)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let pageRows = obj["data"] as? [[String: Any]] else {
                throw MusicError.message("Impossible de lire les morceaux de cette sélection.")
            }
            allRows += pageRows
            next = (obj["next"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "http://api.deezer.com/", with: "https://api.deezer.com/")) }
            if item.kind == "artist" { next = nil }
        }
        var seen = Set<String>()
        return tracks(allRows, artwork: item.artwork).filter { seen.insert($0.id).inserted }
    }
}

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
        return items(try await rows("search/" + kind, query: [URLQueryItem(name: "q", value: term), URLQueryItem(name: "limit", value: "24")]), kind: kind)
    }
    static func normalizeGenre(_ raw: String) -> String {
        let normalized = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let aliases = ["electro": "electro", "electronic": "electro", "electronique": "electro", "hip hop": "rap/hip hop", "hip-hop": "rap/hip hop", "rnb": "r&b", "classical": "classique"]
        return aliases[normalized] ?? normalized
    }
    static func artists(in genre: CatalogItem) async throws -> [CatalogItem] {
        items(try await rows("genre/\(genre.key)/artists"), kind: "artist")
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
                group.addTask { (index, (try? await playlists(query, limit: limit)) ?? []) }
            }
            var sections: [(Int, [CatalogItem])] = []
            for await result in group { sections.append(result) }
            var ids = Set<String>()
            return sections.sorted { $0.0 < $1.0 }.flatMap { $0.1 }.filter { ids.insert($0.id).inserted }
        }
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
        let path = item.kind == "artist" ? "artist/\(item.key)/top" : "\(item.kind)/\(item.key)/tracks"
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

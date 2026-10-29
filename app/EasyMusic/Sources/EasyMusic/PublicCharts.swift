import Foundation

struct ChartSong: Decodable {
    let name: String
    let artistName: String
    let kind: String
}
struct PublicChartSnapshot {
    let tracks: [Track]
    let source: String
}
enum PublicCharts {
    static let iTunesFrance = URL(string: "https://itunes.apple.com/fr/rss/topsongs/limit=50/json")!
    static func parse(_ data: Data) throws -> [ChartSong] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [String: Any], let entries = feed["entry"] as? [[String: Any]] else {
            throw MusicError.message("Le classement France n’a pas pu être lu.")
        }
        return entries.compactMap { entry in
            let content = entry["im:contentType"] as? [String: Any]
            let contentAttributes = content?["attributes"] as? [String: Any]
            let innerContent = content?["im:contentType"] as? [String: Any]
            let innerAttributes = innerContent?["attributes"] as? [String: Any]
            let artist = entry["im:artist"] as? [String: Any]
            let artistAttributes = artist?["attributes"] as? [String: Any]
            let identifier = entry["id"] as? [String: Any]
            let idAttributes = identifier?["attributes"] as? [String: Any]
            guard contentAttributes?["term"] as? String == "Music", innerAttributes?["term"] as? String == "Track",
                  let id = idAttributes?["im:id"] as? String, Int64(id) != nil,
                  let name = (entry["im:name"] as? [String: Any])?["label"] as? String, !name.isEmpty,
                  let artistName = artist?["label"] as? String, !artistName.isEmpty,
                  let raw = artistAttributes?["href"] as? String, let artistURL = URL(string: raw),
                  ["music.apple.com", "itunes.apple.com"].contains(artistURL.host ?? ""), artistURL.pathComponents.contains("artist"),
                  let artistID = artistURL.pathComponents.last, Int64(artistID) != nil else { return nil }
            return ChartSong(name: name, artistName: artistName, kind: "songs")
        }
    }
    static func matches(_ track: Track, song: ChartSong) -> Bool {
        guard Recommendations.contentKey(track.title) == Recommendations.contentKey(song.name) else { return false }
        let expected = creditedArtists(song.artistName)
        let actual = creditedArtists(track.artist)
        return !actual.isEmpty && actual.isSubset(of: expected)
    }
    static func creditedArtists(_ value: String) -> Set<String> {
        // Split explicit collaboration separators, never individual words in an artist's name.
        // Commas alone can belong to names such as "Tyler, The Creator" and are kept intact.
        let separated = value.replacingOccurrences(of: #"(?i)\s+(?:&|feat\.?|ft\.?|featuring|x)\s+"#, with: "|", options: .regularExpression)
        return Set(separated.split(separator: "|").map { Recommendations.contentKey(String($0)) }.filter { !$0.isEmpty })
    }

    static func resolve(_ songs: [ChartSong], limit: Int = 12,
                        search: @escaping (String) async throws -> [Track] = Engine.deezer) async -> [Track] {
        var result: [Track] = [], seen = Set<String>()
        for start in stride(from: 0, to: min(songs.count, 30), by: 3) {
            guard result.count < limit, !Task.isCancelled else { break }
            let chunk = Array(songs[start..<min(start + 3, min(songs.count, 30))])
            let resolved = await withTaskGroup(of: (Int, Track?).self) { group in
                for (index, song) in chunk.enumerated() {
                    group.addTask {
                        let candidates = (try? await search(song.artistName + " " + song.name)) ?? []
                        return (index, candidates.first { matches($0, song: song) })
                    }
                }
                var items: [(Int, Track?)] = []
                for await item in group { items.append(item) }
                return items.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
            }
            result += resolved.filter { seen.insert($0.id).inserted }
        }
        return Array(result.prefix(limit))
    }
    static func loadSongs() async throws -> [ChartSong] {
        var failure: Error = MusicError.message("Le classement France est indisponible.")
        for attempt in 0..<2 {
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 8
                configuration.timeoutIntervalForResource = 12
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: iTunesFrance); request.timeoutInterval = 8
                request.setValue("EasyMusic/0.4.1 (macOS)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw failure }
                return try parse(data)
            } catch {
                failure = error
                if attempt == 0 { try await Task.sleep(nanoseconds: 500_000_000) }
            }
        }
        throw failure
    }
    static func fetch(load: () async throws -> [ChartSong] = loadSongs,
                      search: @escaping (String) async throws -> [Track] = Engine.deezer,
                      fallback: () async throws -> [Track] = { try await Catalog.charts() }) async -> PublicChartSnapshot {
        if let songs = try? await load() {
            let tracks = await resolve(songs, search: search)
            if tracks.count >= 4 { return PublicChartSnapshot(tracks: tracks, source: "Top ventes France · iTunes") }
        }
        return PublicChartSnapshot(tracks: (try? await fallback()) ?? [], source: "Classement Deezer")
    }

}
actor PublicChartCache {
    static let shared = PublicChartCache()
    private var cached: (Date, PublicChartSnapshot)?
    private var loading: Task<PublicChartSnapshot, Never>?
    func current() async -> PublicChartSnapshot {
        if let cached, Date().timeIntervalSince(cached.0) < 1800 { return cached.1 }
        if let loading { return await loading.value }
        let task = Task { await PublicCharts.fetch() }; loading = task
        let result = await task.value
        loading = nil
        if !result.tracks.isEmpty { cached = (Date(), result) }
        return result
    }
}
extension Catalog {
    static func homeCharts() async -> (tracks: [Track], source: String) {
        let result = await PublicChartCache.shared.current()
        return (result.tracks, result.source)
    }
}

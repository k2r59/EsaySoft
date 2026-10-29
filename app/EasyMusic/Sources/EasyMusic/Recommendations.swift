import Foundation

struct MusicInterest: Codable {
    var term: String
    var weight: Double
    var updatedAt: Date
}

enum Recommendations {
    static let generalQueries = ["pop", "rap", "rock", "chanson française", "electro", "jazz", "soul", "latino"]

    static func key(_ term: String) -> String {
        term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func contentKey(_ value: String) -> String {
        key(value).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func genreID(_ query: String) -> Int? {
        let values: [String: Int] = ["pop": 132, "rap": 116, "hip hop": 116, "rap hip hop": 116, "rock": 152,
            "chanson francaise": 52, "variete francaise": 52, "electro": 106, "electronic": 106, "electronique": 106,
            "jazz": 129, "soul": 169, "soul funk": 169, "latino": 197, "livres audio": 457, "audiobook": 457,
            "dance": 113, "r b": 165, "rnb": 165, "alternative": 85, "folk": 466, "reggae": 144,
            "country": 84, "classique": 98, "classical": 98, "films jeux video": 173, "metal": 464,
            "blues": 153, "jeunesse": 95, "musique africaine": 2, "musique arabe": 12, "musique asiatique": 16,
            "musique bresilienne": 75, "musique indienne": 81]
        return values[contentKey(query)]
    }
    static func titleMatches(_ title: String, query: String) -> Bool {
        let words = Set(contentKey(title).split(separator: " ").map(String.init))
        var required = Set(contentKey(query).split(separator: " ").map(String.init))
        if genreID(query) == 52 { return words.contains("chanson") || words.contains("chansons") || (words.contains("variete") && words.contains("francaise")) }
        if genreID(query) == 106 { return !words.intersection(["electro", "electronic", "electronique", "edm"]).isEmpty }
        if genreID(query) == 116 { return words.contains("rap") || (words.contains("hip") && words.contains("hop")) }
        required.subtract(["the", "de", "des", "la", "le", "les", "a", "and", "et"])
        return !required.isEmpty && required.isSubset(of: words)
    }
    /// A name appearing only in a playlist's title or creator is not evidence of its contents.
    static func contentMatches(_ tracks: [[String: Any]], query: String) -> Bool {
        let wanted = contentKey(query)
        guard !wanted.isEmpty, !tracks.isEmpty else { return false }
        let matching = tracks.filter { row in
            let artist = row["artist"] as? [String: Any]
            return contentKey(artist?["name"] as? String ?? "") == wanted || contentKey(row["title"] as? String ?? "") == wanted
        }.count
        return matching >= Int(ceil(Double(tracks.count) * 0.6))
    }
    static func score(_ item: MusicInterest, now: Date) -> Double {
        item.weight * pow(0.5, max(0, now.timeIntervalSince(item.updatedAt)) / (30 * 86400))
    }
    static func record(_ term: String, weight: Double, in interests: [MusicInterest], now: Date = Date()) -> [MusicInterest] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(term.count), !term.contains("://"), weight > 0 else { return interests }
        var items = interests
        if let index = items.firstIndex(where: { key($0.term) == key(term) }) {
            // Repeating a search or replaying an excerpt must not dominate the home page.
            if now.timeIntervalSince(items[index].updatedAt) < 600 && weight <= items[index].weight { return items }
            items[index].weight = min(12, score(items[index], now: now) + weight)
            items[index].updatedAt = now
        } else { items.append(MusicInterest(term: term, weight: weight, updatedAt: now)) }
        return Array(items.sorted { score($0, now: now) > score($1, now: now) }.prefix(64))
    }
    static func queries(_ interests: [MusicInterest], now: Date = Date()) -> [String] {
        interests.filter { score($0, now: now) >= 0.5 }
            .sorted { score($0, now: now) > score($1, now: now) }.prefix(3).map(\.term)
    }
}

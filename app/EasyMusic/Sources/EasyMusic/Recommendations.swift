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

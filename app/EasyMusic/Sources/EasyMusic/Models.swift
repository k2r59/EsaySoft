import Foundation

struct Track: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    var duration: Double?
    var artwork: String?
    var url: String
    var source: String
    var preview: String?
    var isCatalog: Bool = false
    var creditedArtist: String? = nil
    var artistCredits: [String]? = nil
    var durationLabel: String {
        guard let duration, duration.isFinite, duration >= 0 else { return "—" }
        return String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}
struct AudioFormat: Identifiable, Hashable {
    var id: String
    var ext: String
    var codec: String
    var bitrate: Double?
    var label: String {
        "\(ext.uppercased()) · \(codec)" + (bitrate.map { " · ≈\(Int($0)) kb/s" } ?? " · débit non communiqué")
    }
}
struct LocalTrack: Identifiable, Codable {
    var id: UUID = UUID()
    var track: Track
    var path: String
    var downloadedAt: Date = Date()
    var bitrateKbps: Double? = nil
    var bitrateLabel: String {
        guard let value = bitrateKbps, value.isFinite, value > 0 else { return "— kb/s" }
        return "≈ \(Int(value.rounded())) kb/s"
    }
}
struct Playlist: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var importedTracks: [Track]? = nil
    var sourceURL: String? = nil
    var importWarning: String? = nil
    var hasRemoteChanges: Bool? = nil
    var lastSyncCheck: Date? = nil
    var artworkPath: String? = nil
    var addedTracks: [Track]? = nil
}
struct Library: Codable {
    var tracks: [LocalTrack] = []
    var playlists: [Playlist] = []
    var recentCollections: [CatalogItem]? = nil
    var interests: [MusicInterest]? = nil
    var trackPreferences: [TrackPreference]? = nil
}
struct TrackPreference: Identifiable, Codable {
    var id = UUID()
    var track: Track
    var liked = false
    var rating: Int? = nil
}
enum MusicError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum Matching {
    static func sameRecording(_ a: Track, _ b: Track) -> Bool {
        guard !a.artist.isEmpty, !b.artist.isEmpty, let first = a.duration, let second = b.duration,
              first.isFinite, second.isFinite, abs(first - second) <= 2 else { return false }
        return recordingKey(a.title) == recordingKey(b.title)
            && Recommendations.contentKey(a.artist) == Recommendations.contentKey(b.artist)
    }

    static func recordingKey(_ title: String) -> String {
        // Providers spell the same vinyl edit as 7 Inch, 7" or 7''. Keep every version word.
        let canonical = title.replacingOccurrences(of: #"(?i)\b(7|12)\s*(?:''|[\"″”“])"#, with: "$1 inch ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(7|12)\s*inch\b"#, with: "$1 inch", options: .regularExpression)
        return Recommendations.contentKey(canonical)
    }

    static func words(_ text: String) -> Set<String> {
        Set(recordingKey(text).split(separator: " ").map(String.init))
    }
    static func titleForSearch(_ title: String) -> String {
        // Attribution text is not part of the recording name. Keep version markers such as live/remix.
        title.replacingOccurrences(of: #"(?i)\s*\(sur (?:les motifs|un thème) de\b[^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func musicalTitle(_ title: String) -> String {
        // Remove guest credits, preserving version suffixes and ordinary title words such as "Featuring You".
        titleForSearch(title).replacingOccurrences(of: #"(?i)\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]+[\)\]]"#,
            with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.?|featuring)\s+.+?(?=\s+[-–—]\s+|$)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func guestCreditsInTitle(_ title: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"(?i)(?:[\(\[]\s*|\s+)(?:feat\.?|ft\.?|featuring)\s+([^\)\]]+)"#),
              let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else { return nil }
        let value = String(title[range])
        if let suffix = value.range(of: #"\s+[-–—]\s+"#, options: .regularExpression) { return String(value[..<suffix.lowerBound]) }
        return value
    }
    private static func guestNames(_ text: String, known: [String]) -> Set<String> {
        var remaining = Recommendations.contentKey(text)
        var names = Set<String>()
        for name in Set(known.map(Recommendations.contentKey)).sorted(by: { $0.count > $1.count }) where !name.isEmpty {
            let pattern = #"(?<!\S)"# + NSRegularExpression.escapedPattern(for: name) + #"(?!\S)"#
            if remaining.range(of: pattern, options: .regularExpression) != nil {
                names.insert(name)
                remaining = remaining.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
        }
        let rest = remaining.split(separator: " ").filter { $0 != "and" && $0 != "et" }.joined(separator: " ")
        if !rest.isEmpty { names.insert(rest) }
        return names
    }
    static func requestedArtists(_ track: Track) -> [String] {
        if let credits = track.artistCredits, !credits.isEmpty { return credits }
        // Spotify embed separates artists with comma + NBSP. An ordinary comma can belong to an artist name.
        if track.id.hasPrefix("spotify:") || track.source == "Spotify" {
            return track.artist.components(separatedBy: ",\u{00a0}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return track.artist.isEmpty ? [] : [track.artist]
    }
    static func creditedArtists(_ track: Track, requested: [String]) -> [String]? {
        if let credits = track.artistCredits, !credits.isEmpty { return credits }
        guard let text = track.creditedArtist else { return nil }
        let parts = text.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.?|featuring)\s+"#, with: "|", options: .regularExpression).components(separatedBy: "|")
        return parts.enumerated().flatMap { index, part -> [String] in
            if index > 0 { return guestNames(part, known: Array(requested.dropFirst())).sorted() }
            if requested.contains(where: { Recommendations.contentKey($0) == Recommendations.contentKey(part) }) { return [part] }
            return part.components(separatedBy: CharacterSet(charactersIn: ",，"))
        }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private static func guestCreditKey(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let key = Recommendations.contentKey(compact)
        // Secondary-credit spelling differences observed across the same official catalogue recordings.
        let aliases = ["les sages poetes de la rue": "sages poetes de la rue", "the insomniak": "insomniak"]
        return aliases[key] ?? key
    }
    static func score(_ candidate: Track, for target: Track) -> Double {
        func vinylSizes(_ title: String) -> Set<String> {
            let tokens = recordingKey(title).split(separator: " ")
            var sizes = Set<String>()
            for index in tokens.indices where index > 0 && tokens[index] == "inch" {
                if tokens[index - 1] == "7" || tokens[index - 1] == "12" { sizes.insert(String(tokens[index - 1])) }
            }
            return sizes
        }
        let requestedSizes = vinylSizes(target.title), availableSizes = vinylSizes(candidate.title)
        if !requestedSizes.isEmpty, !availableSizes.isEmpty, requestedSizes.isDisjoint(with: availableSizes) { return 0 }
        let requested = requestedArtists(target)
        let listedGuests = Array(requested.dropFirst())
        let candidateCredits = creditedArtists(candidate, requested: requested)
        let knownGuests = listedGuests + Array((candidateCredits ?? []).dropFirst())
        var expectedGuests = Set(listedGuests.map(guestCreditKey))
        if let titleGuests = guestCreditsInTitle(target.title) {
            expectedGuests.formUnion(guestNames(titleGuests, known: knownGuests).map(guestCreditKey))
        }
        if !expectedGuests.isEmpty, let actualGuests = guestCreditsInTitle(candidate.title) {
            let foundGuests = Set(guestNames(actualGuests, known: knownGuests).map(guestCreditKey))
            guard foundGuests.isSubset(of: expectedGuests) else { return 0 }
        }
        let primary = requested.first ?? target.artist
        if let credits = candidateCredits, !primary.isEmpty {
            guard let lead = credits.first, Recommendations.contentKey(lead) == Recommendations.contentKey(primary) else { return 0 }
            if !expectedGuests.isEmpty, credits.count > 1 {
                let guests = Set(credits.dropFirst().map(guestCreditKey))
                guard expectedGuests.isSubset(of: guests) else { return 0 }
            }
        }
        let title = words(musicalTitle(target.title)), artist = words(primary)
        let available = words(candidate.title + " " + candidate.artist)
        guard !title.isEmpty else { return 0 }
        let titleScore = Double(title.intersection(available).count) / Double(title.count)
        let artistScore = artist.isEmpty ? 0 : Double(artist.intersection(available).count) / Double(artist.count)
        var score = titleScore * 0.55 + artistScore * 0.3
        if let a = candidate.duration, let b = target.duration { score += max(0, 1 - abs(a-b) / 20) * 0.15 }
        let unwanted: Set<String> = ["cover", "karaoke", "remix", "live", "sped", "slowed", "instrumental", "medley", "extended", "radio"]
        if available.intersection(unwanted) != words(target.title).intersection(unwanted) { score -= 0.35 }
        return score
    }
}

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
        if let credited = candidate.creditedArtist, !target.artist.isEmpty {
            let names = credited.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.?|featuring)\s+|\s*&\s*|\s*,\s*"#, with: "|", options: .regularExpression)
                .split(separator: "|").map { Recommendations.contentKey(String($0)) }
            let artist = Recommendations.contentKey(target.artist)
            guard names.contains(artist) || Recommendations.contentKey(credited) == artist else { return 0 }
        }
        let title = words(titleForSearch(target.title)), artist = words(target.artist)
        let available = words(candidate.title + " " + candidate.artist)
        guard !title.isEmpty else { return 0 }
        let titleScore = Double(title.intersection(available).count) / Double(title.count)
        let artistScore = artist.isEmpty ? 0 : Double(artist.intersection(available).count) / Double(artist.count)
        var score = titleScore * 0.55 + artistScore * 0.3
        if let a = candidate.duration, let b = target.duration { score += max(0, 1 - abs(a-b) / 20) * 0.15 }
        let unwanted: Set<String> = ["cover", "karaoke", "remix", "live", "sped", "slowed", "instrumental"]
        if available.intersection(unwanted) != words(target.title).intersection(unwanted) { score -= 0.35 }
        return score
    }
}

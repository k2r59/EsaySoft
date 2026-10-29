import Foundation
import CryptoKit

struct Engine {
    static func executable(_ name: String) -> String? {
        let paths: [String?] = [Bundle.main.resourceURL?.appendingPathComponent("bin/\(name)").path,
                     FileManager.default.currentDirectoryPath + "/.tools/runtime/\(name)",
                     FileManager.default.currentDirectoryPath + "/.tools/\(name)",
                     "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return paths.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func run(_ args: [String], timeout: TimeInterval = 100,
                    progress: (@Sendable (String) -> Void)? = nil) async throws -> String {
        guard let binary = executable("yt-dlp") else { throw MusicError.message("Le moteur de téléchargement est absent. Relancez scripts/build-app.sh.") }
        return try await Task.detached {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: file) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            var base = ["--ignore-config", "--no-playlist", "--no-colors", "--no-warnings", "--socket-timeout", "15", "--retries", "1"]
            if let node = executable("node") { base += ["--js-runtimes", "node:\(node)"] }
            process.arguments = base + args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = env
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            let start = Date()
            while process.isRunning {
                if Date().timeIntervalSince(start) > timeout {
                    process.terminate()
                    throw MusicError.message("La source met trop de temps à répondre. Réessayez ou choisissez une autre version.")
                }
                if let progress, let output = try? String(contentsOf: file, encoding: .utf8) { progress(output) }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            let output = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            guard process.terminationStatus == 0 else {
                let error = output.components(separatedBy: .newlines).last(where: { $0.contains("ERROR:") }) ?? String(output.suffix(500))
                throw AudioFailure.classify(error)
            }
            return output
        }.value
    }
    static func jsonLines(_ output: String) -> [[String: Any]] {
        output.components(separatedBy: .newlines).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }
    static func track(_ json: [String: Any], source: String) -> Track? {
        guard let title = json["title"] as? String, let id = json["id"] as? String else { return nil }
        let raw = (json["webpage_url"] as? String) ?? (json["url"] as? String) ?? ""
        let url = raw.hasPrefix("http") ? raw : (source == "YouTube" ? "https://www.youtube.com/watch?v=\(id)" : "")
        guard !url.isEmpty else { return nil }
        let thumbs = json["thumbnails"] as? [[String: Any]]
        return Track(id: source + ":" + id, title: title,
                     artist: (json["artist"] as? String) ?? (json["uploader"] as? String) ?? (json["channel"] as? String) ?? source,
                     duration: json["duration"] as? Double,
                     artwork: (json["thumbnail"] as? String) ?? (thumbs?.last?["url"] as? String),
                     url: url, source: source)
    }
    static func search(_ query: String, source: String, count: Int = 8) async throws -> [Track] {
        let prefix = source == "SoundCloud" ? "scsearch" : "ytsearch"
        let output = try await run(["--flat-playlist", "--dump-json", "--", "\(prefix)\(count):\(query)"])
        return jsonLines(output).compactMap { track($0, source: source) }
    }
    static func request(_ url: URL, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicError.message("Le service est temporairement indisponible.")
        }
        return data
    }
    static func deezer(_ query: String) async throws -> [Track] {
        var parts = URLComponents(string: "https://api.deezer.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "12")]
        let data = try await request(parts.url!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = root["data"] as? [[String: Any]] else { throw MusicError.message("Recherche Deezer indisponible.") }
        return Catalog.tracks(rows)
    }

    static let supportedHosts = ["youtube.com", "youtu.be", "soundcloud.com", "bandcamp.com", "jamendo.com", "audiomack.com", "archive.org", "vimeo.com", "mixcloud.com"]
    static func isSupported(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return supportedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func spotifyTitle(_ url: URL) async throws -> String {
        guard url.host == "open.spotify.com", url.pathComponents.contains("track") else {
            throw MusicError.message("Collez un lien Spotify vers un morceau individuel.")
        }
        var parts = URLComponents(string: "https://open.spotify.com/oembed")!
        parts.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        let data = try await request(parts.url!)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let title = obj["title"] as? String else { throw MusicError.message("Ce lien Spotify n’a pas pu être identifié.") }
        return title
    }
    static func inspect(_ url: String) async throws -> (Track, [AudioFormat]) {
        let output = try await run(["--skip-download", "--dump-json", "--", url])
        guard let obj = jsonLines(output).first else { throw MusicError.message("Aucune piste audio trouvée.") }
        let source = (obj["extractor_key"] as? String) ?? "Source"
        guard let item = track(obj, source: source) else { throw MusicError.message("Impossible de lire ce morceau.") }
        return (item, formats(obj))
    }
    static func formats(_ obj: [String: Any]) -> [AudioFormat] {
        let rows = (obj["formats"] as? [[String: Any]]) ?? [obj]
        return rows.compactMap { row -> AudioFormat? in
            guard row["has_drm"] as? Bool != true,
                  let codec = row["acodec"] as? String, codec != "none",
                  (row["vcodec"] as? String ?? "none") == "none",
                  let id = row["format_id"] as? String, let ext = row["ext"] as? String else { return nil }
            return AudioFormat(id: id, ext: ext, codec: codec, bitrate: row["abr"] as? Double)
        }.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
    }
    static func previewClip(_ track: Track) async throws -> URL {
        guard let ffmpeg = executable("ffmpeg") else { return try await previewURL(track.url) }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyMusic/Previews", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data(track.url.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = cache.appendingPathComponent(key + ".m4a")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        let work = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let output = try await run(["--ffmpeg-location", URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path,
                                    "--download-sections", "*0-30", "-f", "bestaudio", "-x", "--audio-format", "m4a",
                                    "--print", "after_move:FILE:%(filepath)s", "--no-simulate", "-o", work.appendingPathComponent("preview.%(ext)s").path, "--", track.url], timeout: 120)
        guard let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("FILE:") }) else { throw MusicError.message("Impossible de préparer cet extrait.") }
        let ready = URL(fileURLWithPath: String(line.dropFirst(5)))
        guard FileManager.default.fileExists(atPath: ready.path) else { throw MusicError.message("L’extrait n’a pas pu être enregistré.") }
        if !FileManager.default.fileExists(atPath: cached.path) { try FileManager.default.moveItem(at: ready, to: cached) }
        return cached
    }
    static func previewURL(_ url: String) async throws -> URL {
        let output = try await run(["--get-url", "-f", "bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio", "--", url])
        guard let line = output.components(separatedBy: .newlines).first(where: { $0.hasPrefix("https://") }), let result = URL(string: line) else {
            throw MusicError.message("Aucun extrait accessible pour cette source.")
        }
        return result
    }
    static func downloadArguments(track: Track, format: String?, folder: URL) -> [String] {
        ["--concurrent-fragments", "4", "--newline", "--progress", "--progress-template", "download:PROGRESS:%(progress._percent_str)s", "--print", "after_move:FILE:%(filepath)s",
         "--no-simulate", "--no-overwrites", "-f", format.map { "\($0)[vcodec=none][acodec!=none]" } ?? "bestaudio", "-P", folder.path,
         "-o", "%(title).160B [%(id)s].%(ext)s", "--", track.url]
    }
}

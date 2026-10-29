import Foundation
import AVFoundation

struct AudioStream {
    let url: URL
    let source: Track
    let userAgent: String?
    init(url: URL, source: Track, userAgent: String? = nil) {
        self.url = url; self.source = source; self.userAgent = userAgent
    }
    func makeAsset() -> AVURLAsset {
        AVURLAsset(url: url, options: userAgent.map { [AVURLAssetHTTPUserAgentKey: $0] })
    }
}

enum AudioStreaming {
    // Every branch explicitly excludes video. No extraction, conversion, output path or download section.
    static let formatSelection = "bestaudio[vcodec=none][ext=m4a][acodec^=mp4a]/bestaudio[vcodec=none][ext=m4a][acodec=aac]/bestaudio[vcodec=none][ext=mp3]/bestaudio[vcodec=none][protocol^=m3u8][acodec^=mp4a]"
    static func extractionArguments(_ url: String) -> [String] {
        ["--skip-download", "--dump-single-json", "-f", formatSelection, "--", url]
    }
    static func resolve(_ target: Track, excluding: Set<String> = []) async throws -> AudioStream {
        let deadline = Date().addingTimeInterval(55)
        func remaining(_ cap: TimeInterval) throws -> TimeInterval {
            try Task.checkCancellation()
            let value = deadline.timeIntervalSinceNow
            guard value > 0 else { throw MusicError.message("La préparation de la lecture prend trop de temps. Réessayez dans un instant.") }
            return min(cap, value)
        }
        return try await run(target: target, excluding: excluding, search: { query, service in
            let prefix = service == "SoundCloud" ? "scsearch" : "ytsearch"
            let output = try await StreamingProcess.run(["--flat-playlist", "--dump-json", "--", "\(prefix)5:\(query)"], timeout: try remaining(12))
            return Engine.jsonLines(output).compactMap { Engine.track($0, source: service) }
        }, extract: { candidate in
            let output = try await StreamingProcess.run(extractionArguments(candidate.url), timeout: try remaining(15))
            guard let json = Engine.jsonLines(output).first else { throw AudioFailure.unavailable }
            let stream = try selectedStream(json, source: candidate)
            try await validate(stream, expectedDuration: target.duration ?? stream.source.duration, timeout: try remaining(8))
            return stream
        })
    }
    static func run(target: Track, excluding: Set<String> = [],
                    search: (String, String) async throws -> [Track],
                    extract: (Track) async throws -> AudioStream) async throws -> AudioStream {
        var attempted = excluding
        try Task.checkCancellation()
        if !target.isCatalog, attempted.insert(target.url).inserted {
            do { return try await extract(target) }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        let services = target.isCatalog || target.source == "YouTube" ? ["SoundCloud", "YouTube"] : ["YouTube", "SoundCloud"]
        for service in services {
            try Task.checkCancellation()
            let candidates: [Track]
            do { candidates = try await search(target.artist + " " + Matching.titleForSearch(target.title), service) }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation(); continue }
            let ranked = candidates.filter { !$0.isCatalog && durationMatches($0.duration, target.duration) && Matching.score($0, for: target) >= 0.85 }
                .sorted { Matching.score($0, for: target) > Matching.score($1, for: target) }
            var count = 0
            for candidate in ranked where attempted.insert(candidate.url).inserted {
                guard count < 2 else { break }; count += 1
                try Task.checkCancellation()
                do { return try await extract(candidate) }
                catch is CancellationError { throw CancellationError() }
                catch { try Task.checkCancellation() }
            }
        }
        throw MusicError.message("Aucun flux audio complet et suffisamment proche n’est accessible pour « \(target.title) ».")
    }
    static func durationMatches(_ actual: Double?, _ expected: Double?) -> Bool {
        guard let actual, let expected, actual.isFinite, expected.isFinite, actual > 0, expected > 0 else { return true }
        return abs(actual - expected) <= max(20, expected * 0.12)
    }
    static func selectedStream(_ json: [String: Any], source: Track) throws -> AudioStream {
        guard json["has_drm"] as? Bool != true, json["is_preview"] as? Bool != true,
              json["vcodec"] as? String == "none", let codec = json["acodec"] as? String,
              codec == "mp3" || codec == "aac" || codec.hasPrefix("mp4a"),
              let ext = json["ext"] as? String, ["m4a", "mp3", "aac", "mp4"].contains(ext),
              let raw = json["url"] as? String, let url = URL(string: raw), url.scheme == "https", url.host != nil else {
            throw AudioFailure.unavailable
        }
        let markers = [json["format_id"], json["format_note"]].compactMap { $0 as? String }.joined(separator: " ").lowercased()
        guard !markers.contains("preview"), !markers.contains("sample"),
              json["requested_formats"] == nil else { throw AudioFailure.unavailable }
        var resolved = source
        if let duration = json["duration"] as? Double, duration.isFinite, duration > 0 { resolved.duration = duration }
        let headers = json["http_headers"] as? [String: String]
        let userAgent = headers?["User-Agent"].flatMap {
            $0.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) ? nil : $0
        }
        return AudioStream(url: url, source: resolved, userAgent: userAgent)
    }
    static func validate(_ stream: AudioStream, expectedDuration: Double?, timeout: TimeInterval = 8) async throws {
        let asset = stream.makeAsset()
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let playable = try await asset.load(.isPlayable)
                    guard playable else { throw AudioFailure.unavailable }
                    let video = try await asset.loadTracks(withMediaType: .video)
                    let audio = try await asset.loadTracks(withMediaType: .audio)
                    guard video.isEmpty, !audio.isEmpty else { throw AudioFailure.unavailable }
                    if let expectedDuration, expectedDuration > 40 {
                        let duration = try await asset.load(.duration).seconds
                        guard duration.isFinite, duration >= expectedDuration * 0.8, duration <= expectedDuration * 1.2 + 10 else { throw AudioFailure.unavailable }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                    throw AudioFailure.network
                }
                defer { group.cancelAll(); asset.cancelLoading() }
                _ = try await group.next()
            }
        } onCancel: { asset.cancelLoading() }
    }
}

/// Process output stays in memory. Cancellation stops yt-dlp instead of leaving a detached extraction running.
private enum StreamingProcess {
    static func run(_ args: [String], timeout: TimeInterval) async throws -> String {
        guard let binary = Engine.executable("yt-dlp") else { throw MusicError.message("Le moteur audio est absent.") }
        let holder = StreamingProcessHolder()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            var base = ["--ignore-config", "--no-playlist", "--no-colors", "--no-warnings", "--no-cache-dir", "--socket-timeout", "8", "--retries", "0"]
            if let node = Engine.executable("node") { base += ["--js-runtimes", "node:\(node)"] }
            process.arguments = base + args
            process.standardOutput = output; process.standardError = errors
            try holder.start(process)
            defer { holder.stop() }
            async let stdout = read(output.fileHandleForReading)
            async let stderr = read(errors.fileHandleForReading)
            let start = Date()
            while process.isRunning {
                try Task.checkCancellation()
                if Date().timeIntervalSince(start) >= timeout { holder.stop(); throw AudioFailure.network }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let data = await stdout, errorData = await stderr
            try Task.checkCancellation()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else { throw AudioFailure.classify(errorText) }
            return String(data: data, encoding: .utf8) ?? ""
        } onCancel: { holder.stop() }
    }
    private static func read(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                try? handle.close()
                continuation.resume(returning: data)
            }
        }
    }
}
private final class StreamingProcessHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    func start(_ value: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        try value.run(); process = value
    }
    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if process?.isRunning == true { process?.terminate() }
    }
}

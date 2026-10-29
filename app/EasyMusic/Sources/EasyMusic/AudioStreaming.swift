import Foundation
import AVFoundation

struct AudioStream {
    let url: URL
    let source: Track
    let userAgent: String?
    private let asset: AVURLAsset
    init(url: URL, source: Track, userAgent: String? = nil) {
        self.url = url; self.source = source; self.userAgent = userAgent
        asset = AVURLAsset(url: url, options: userAgent.map { [AVURLAssetHTTPUserAgentKey: $0] })
    }
    func makeAsset() -> AVURLAsset {
        asset
    }
}

enum AudioStreaming {
    static func warmUpRuntime() async {
        guard let runtime = Bundle.main.resourceURL?.appendingPathComponent("bin/yt-dlp-runtime/yt-dlp_macos"),
              FileManager.default.isExecutableFile(atPath: runtime.path) else { return }
        // Prime the installed executable locally. No catalogue or audio request.
        _ = try? await StreamingProcess.run(["--version"], timeout: 8)
    }
    // Every branch explicitly excludes video. No extraction, conversion, output path or download section.
    // YouTube DASH M4A can report twice the duration in AVFoundation. Native HLS has correct timing.
    static let formatSelection = "bestaudio[vcodec=none][protocol^=m3u8]/bestaudio[vcodec=none][ext=m4a][acodec^=mp4a]/bestaudio[vcodec=none][ext=m4a][acodec=aac]/bestaudio[vcodec=none][ext=mp3]"
    static func extractionArguments(_ url: String, fast: Bool = false) -> [String] {
        let profile = fast ? ["--extractor-args", "youtube:player_client=visionos;player_skip=initial_data;skip=dash,translated_subs"] : []
        return profile + ["--skip-download", "--dump-single-json", "-f", formatSelection, "--", url]
    }
    static func hasFastProfile(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
    static func candidateStream(_ candidate: Track, expectedDuration: Double?,
                                read: ([String], TimeInterval) async throws -> [String: Any],
                                validate: (AudioStream) async throws -> Void) async throws -> AudioStream {
        let profiles = hasFastProfile(candidate.url) ? [true, false] : [false]
        for fast in profiles {
            try Task.checkCancellation()
            do {
                let json = try await read(extractionArguments(candidate.url, fast: fast), fast ? 5 : 15)
                guard durationMatches(json["duration"] as? Double, expectedDuration) else { throw AudioFailure.unavailable }
                return try await firstPlayable(streams(json, source: candidate), validate: validate)
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                if !fast { throw error }
            }
        }
        throw AudioFailure.unavailable
    }
    static func resolve(_ target: Track, excluding: Set<String> = []) async throws -> AudioStream {
        try Task.checkCancellation()
        if let cached = await AudioStreamCache.shared.value(for: target, excluding: excluding) { return cached }
        let deadline = Date().addingTimeInterval(55)
        func remaining(_ cap: TimeInterval) throws -> TimeInterval {
            try Task.checkCancellation()
            let value = deadline.timeIntervalSinceNow
            guard value > 0 else { throw MusicError.message("La préparation de la lecture prend trop de temps. Réessayez dans un instant.") }
            return min(cap, value)
        }
        let stream = try await run(target: target, excluding: excluding, search: { query, service in
            let prefix = service == "SoundCloud" ? "scsearch" : "ytsearch"
            let output = try await StreamingProcess.run(["--flat-playlist", "--dump-json", "--", "\(prefix)5:\(query)"], timeout: try remaining(12))
            return Engine.jsonLines(output).compactMap { Engine.track($0, source: service) }
        }, extract: { candidate in
            try await candidateStream(candidate, expectedDuration: target.duration, read: { args, cap in
                let output = try await StreamingProcess.run(args, timeout: try remaining(cap))
                guard let json = Engine.jsonLines(output).first else { throw AudioFailure.unavailable }
                return json
            }) { stream in
                try await validate(stream, expectedDuration: target.duration ?? stream.source.duration, timeout: try remaining(8))
            }
        })
        try Task.checkCancellation()
        await AudioStreamCache.shared.insert(stream, for: target)
        return stream
    }
    static func run(target: Track, excluding: Set<String> = [],
                    search: @escaping (String, String) async throws -> [Track],
                    extract: @escaping (Track) async throws -> AudioStream) async throws -> AudioStream {
        var attempted = excluding
        try Task.checkCancellation()
        if !target.isCatalog, attempted.insert(target.url).inserted {
            do { return try await extract(target) }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        let services = target.isCatalog || target.source == "YouTube" ? ["SoundCloud", "YouTube"] : ["YouTube", "SoundCloud"]
        let excluded = attempted
        // Race complete validated audio streams, not just search results: a slow extraction must not block the other service.
        return try await withThrowingTaskGroup(of: AudioStream?.self) { group in
            for service in services {
                group.addTask {
                    let candidates: [Track]
                    do { candidates = try await search(target.artist + " " + Matching.titleForSearch(target.title), service) }
                    catch is CancellationError { throw CancellationError() }
                    catch { return nil }
                    let ranked = candidates.filter { !$0.isCatalog && durationMatches($0.duration, target.duration) && Matching.score($0, for: target) >= 0.85 }
                        .sorted { Matching.score($0, for: target) > Matching.score($1, for: target) }
                    var seen = excluded, count = 0
                    for candidate in ranked where seen.insert(candidate.url).inserted {
                        guard count < 2 else { break }; count += 1
                        try Task.checkCancellation()
                        do { return try await extract(candidate) }
                        catch is CancellationError { throw CancellationError() }
                        catch { try Task.checkCancellation() }
                    }
                    return nil
                }
            }
            defer { group.cancelAll() }
            for try await stream in group {
                try Task.checkCancellation()
                if let stream { return stream }
            }
            try Task.checkCancellation()
            throw MusicError.message("Aucun flux audio complet et suffisamment proche n’est accessible pour « \(target.title) ».")
        }
    }
    static func durationMatches(_ actual: Double?, _ expected: Double?) -> Bool {
        guard let actual, let expected, actual.isFinite, expected.isFinite, actual > 0, expected > 0 else { return true }
        return abs(actual - expected) <= max(20, expected * 0.12)
    }
    static func selectedStream(_ json: [String: Any], source: Track) throws -> AudioStream {
        let codec = json["acodec"] as? String
        let hls = (json["protocol"] as? String)?.hasPrefix("m3u8") == true
        // Some HLS audio manifests omit CODECS. The ready player item verifies the actual audio tracks.
        let compatible = codec == "mp3" || codec == "aac" || codec?.hasPrefix("mp4a") == true || (hls && codec == nil)
        guard json["has_drm"] as? Bool != true, json["is_preview"] as? Bool != true,
              json["vcodec"] as? String == "none", compatible,
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
    static func streams(_ json: [String: Any], source: Track) -> [AudioStream] {
        var rows = [json]
        let formats = (json["formats"] as? [[String: Any]] ?? []).reversed()
        // Prefer HLS, then other supported audio formats, without extracting the same page again.
        rows += formats.filter { ($0["protocol"] as? String)?.hasPrefix("m3u8") == true }
        rows += formats.filter { ($0["protocol"] as? String)?.hasPrefix("m3u8") != true }
        var seen = Set<URL>()
        return rows.compactMap { row in
            var candidate = row
            for key in ["duration", "is_preview", "http_headers"] where candidate[key] == nil { candidate[key] = json[key] }
            if json["has_drm"] as? Bool == true { candidate["has_drm"] = true }
            if json["is_preview"] as? Bool == true { candidate["is_preview"] = true }
            guard let stream = try? selectedStream(candidate, source: source), seen.insert(stream.url).inserted else { return nil }
            return stream
        }.prefix(3).map { $0 }
    }
    static func firstPlayable(_ streams: [AudioStream], validate: (AudioStream) async throws -> Void) async throws -> AudioStream {
        for stream in streams {
            try Task.checkCancellation()
            do { try await validate(stream); return stream }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        throw AudioFailure.unavailable
    }
    @MainActor static func validate(_ stream: AudioStream, expectedDuration: Double?, timeout: TimeInterval = 8) async throws {
        // HLS tracks appear on the ready item, not necessarily on AVURLAsset.loadTracks before playback.
        let item = AVPlayerItem(asset: stream.makeAsset()), player = AVPlayer()
        player.isMuted = true; item.preferredForwardBufferDuration = 1
        player.replaceCurrentItem(with: item)
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if item.status == .failed { throw AudioFailure.unavailable }
            if item.status == .readyToPlay, !item.tracks.isEmpty {
                let media = item.tracks.compactMap { $0.assetTrack?.mediaType }
                guard !media.contains(.video), media.contains(.audio) else { throw AudioFailure.unavailable }
                if let expectedDuration, expectedDuration > 40 {
                    let duration = item.duration.seconds
                    guard duration.isFinite, duration >= expectedDuration * 0.8, duration <= expectedDuration * 1.2 + 10 else { throw AudioFailure.unavailable }
                }
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw AudioFailure.network
    }
}

actor AudioStreamCache {
    static let shared = AudioStreamCache()
    private struct Entry { let stream: AudioStream; let expires: Date }
    private var entries: [String: Entry] = [:]
    private func key(_ track: Track) -> String { track.id + "|" + track.url }
    func value(for track: Track, excluding: Set<String> = [], now: Date = Date()) -> AudioStream? {
        guard let entry = entries[key(track)] else { return nil }
        guard entry.expires > now, !excluding.contains(entry.stream.source.url) else { entries[key(track)] = nil; return nil }
        return entry.stream
    }
    func insert(_ stream: AudioStream, for track: Track, now: Date = Date()) {
        entries = entries.filter { $0.value.expires > now }
        var expiry = now.addingTimeInterval(15 * 60)
        if let value = URLComponents(url: stream.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "expire" || $0.name == "expires" })?.value,
           let seconds = Double(value) { expiry = min(expiry, Date(timeIntervalSince1970: seconds - 30)) }
        if entries.count >= 64, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key { entries[oldest] = nil }
        entries[key(track)] = Entry(stream: stream, expires: expiry)
    }
}

/// Process output stays in memory. Cancellation stops yt-dlp instead of leaving a detached extraction running.
enum StreamingProcess {
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

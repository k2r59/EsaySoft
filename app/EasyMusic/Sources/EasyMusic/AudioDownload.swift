import Foundation

enum AudioFailure: LocalizedError {
    case protectedAudio, unavailable, network, localFile, other
    var canTryAnotherSource: Bool { if case .localFile = self { return false }; return true }
    var errorDescription: String? {
        switch self {
        case .protectedAudio: return "Cette source audio est protégée."
        case .unavailable: return "Ce flux audio n’est pas accessible dans la qualité demandée."
        case .network: return "La source audio ne répond pas."
        case .localFile: return "Impossible d’enregistrer le fichier. Vérifiez le dossier et l’espace disponible."
        case .other: return "Cette source audio est momentanément indisponible."
        }
    }
    static func classify(_ output: String) -> AudioFailure {
        let text = output.lowercased()
        if text.contains("no space left") || text.contains("permission denied") || text.contains("read-only file system") { return .localFile }
        if text.contains("drm") || text.contains("protected") { return .protectedAudio }
        if text.contains("timed out") || text.contains("timeout") || text.contains("unable to download") { return .network }
        if text.contains("format") || text.contains("private") || text.contains("unavailable") || text.contains("removed") { return .unavailable }
        return .other
    }
}

enum AudioDownload {
    /// The same confidence threshold applies to every fallback. No stream protection is bypassed.
    static func run(target: Track, preferred: String?,
                    search: (String, String) async throws -> [Track],
                    transfer: (Track, String?) async throws -> String,
                    inspect: (Track) async throws -> Track? = inspectCandidate,
                    status: (String) -> Void = { _ in }) async throws -> (Track, String) {
        var attempted = Set<String>()
        var lastFailure: Error?
        try Task.checkCancellation()
        if !target.isCatalog {
            attempted.insert(target.url)
            do { return (target, try await transfer(target, preferred)) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                if let failure = error as? AudioFailure, !failure.canTryAnotherSource { throw failure }
                lastFailure = error
            }
        }
        // YouTube first for catalogue tracks. If the requested source failed, try the other service first.
        let services = target.source == "YouTube" ? ["SoundCloud", "YouTube"] : ["YouTube", "SoundCloud"]
        for service in services {
            try Task.checkCancellation()
            status(lastFailure == nil ? "Recherche audio sur \(service)…" : "Autre source audio : \(service)…")
            let candidates: [Track]
            do { candidates = try await search(target.artist + " " + Matching.titleForSearch(target.title), service) }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation(); lastFailure = error; continue }
            try Task.checkCancellation()
            let ranked = candidates.filter { !$0.isCatalog && AudioStreaming.durationMatches($0.duration, target.duration) && Matching.score($0, for: target) >= 0.85 }
                .sorted { Matching.score($0, for: target) > Matching.score($1, for: target) }
            var count = 0
            for candidate in ranked where attempted.insert(candidate.url).inserted {
                guard count < 2 else { break }; count += 1
                do { return (candidate, try await transfer(candidate, nil)) }
                catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    if let failure = error as? AudioFailure, !failure.canTryAnotherSource { throw failure }
                    lastFailure = error
                }
            }
            // Try known matches immediately. Inspect only rejected, plausible collaborations when those fail.
            // Publishing-channel snippets are enriched first; stop at the first successful transfer.
            if count < 2, Matching.requestedArtists(target).count > 1 {
                let uncertain = candidates.filter { !attempted.contains($0.url) && Matching.score($0, for: target) < 0.85 && canInspect($0, for: target) }
                    .sorted { ($0.creditedArtist != nil ? 1 : 0) > ($1.creditedArtist != nil ? 1 : 0) }
                for candidate in uncertain.prefix(2) {
                    try Task.checkCancellation()
                    do {
                        guard let enriched = try await inspect(candidate), AudioStreaming.durationMatches(enriched.duration, target.duration),
                              Matching.score(enriched, for: target) >= 0.85, attempted.insert(enriched.url).inserted else { continue }
                        try Task.checkCancellation()
                        guard count < 2 else { break }; count += 1
                        return (enriched, try await transfer(enriched, nil))
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation()
                        if let failure = error as? AudioFailure, !failure.canTryAnotherSource { throw failure }
                        lastFailure = error
                    }
                }
            }
        }
        throw MusicError.message("Aucune version audio accessible et suffisamment proche pour « \(target.title) ». Vous pouvez réessayer plus tard.")
    }

    static func canInspect(_ candidate: Track, for target: Track) -> Bool {
        guard !candidate.isCatalog, AudioStreaming.durationMatches(candidate.duration, target.duration) else { return false }
        let requested = Matching.words(Matching.musicalTitle(target.title))
        guard !requested.isEmpty else { return false }
        let found = Matching.words(candidate.title)
        return Double(requested.intersection(found).count) / Double(requested.count) >= 0.75
    }
    static func inspectCandidate(_ candidate: Track) async throws -> Track? {
        let output = try await StreamingProcess.run(["--skip-download", "--dump-single-json", "--", candidate.url], timeout: 10)
        try Task.checkCancellation()
        guard let json = Engine.jsonLines(output).first,
              json["has_drm"] as? Bool != true, json["is_preview"] as? Bool != true,
              var enriched = Engine.track(json, source: candidate.source) else { return nil }
        enriched.artistCredits = json["artists"] as? [String]
        return enriched
    }

    static func transfer(_ source: Track, format: String?, folder: URL, export: String,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        // Serialize identical URLs only: two playlist entries must never write the same file together.
        await DownloadFileLock.shared.acquire(source.url)
        do {
            let ffmpeg = export == "original" ? nil : Engine.executable("ffmpeg")
            let output = try await withOptionalArtwork(include: ffmpeg != nil) { artwork in
                var args = Engine.downloadArguments(track: source, format: format, folder: folder)
                if let ffmpeg {
                    var conversion = ["--ffmpeg-location", URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path,
                        "-x", "--audio-format", export, "--audio-quality", "0", "--embed-metadata"]
                    if artwork { conversion += ["--convert-thumbnails", "jpg", "--embed-thumbnail"] }
                    args.insert(contentsOf: conversion, at: 0)
                }
                return try await Engine.run(args, timeout: 900) { output in
                    if let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("PROGRESS:") }),
                       let value = Double(line.dropFirst(9).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                        progress(min(1, max(0, value / 100)))
                    }
                }
            }
            guard let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("FILE:") }) else { throw AudioFailure.other }
            let path = String(line.dropFirst(5))
            guard FileManager.default.fileExists(atPath: path) else { throw AudioFailure.localFile }
            await DownloadFileLock.shared.release(source.url)
            return path
        } catch {
            await DownloadFileLock.shared.release(source.url)
            throw error
        }
    }
    static func withOptionalArtwork(include: Bool, execute: (Bool) async throws -> String) async throws -> String {
        try Task.checkCancellation()
        do {
            let result = try await execute(include)
            try Task.checkCancellation()
            return result
        } catch is CancellationError { throw CancellationError() }
        catch AudioFailure.other where include {
            // A failed optional postprocessor must not turn complete, usable audio into a failed track.
            // Retry conversion and metadata once, with all audio/DRM checks still enabled.
            try Task.checkCancellation()
            let result = try await execute(false)
            try Task.checkCancellation()
            return result
        }
    }
}

actor DownloadFileLock {
    static let shared = DownloadFileLock()
    private var occupied = Set<String>()
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    func acquire(_ url: String) async {
        if occupied.insert(url).inserted { return }
        await withCheckedContinuation { waiters[url, default: []].append($0) }
    }
    func release(_ url: String) {
        if var queue = waiters[url], !queue.isEmpty {
            let next = queue.removeFirst(); waiters[url] = queue; next.resume()
        } else { occupied.remove(url); waiters[url] = nil }
    }
}

struct ActiveDownload: Identifiable {
    let track: Track
    var id: String { track.id }
    var progress: Double = 0
    var phase = "Préparation de l’audio…"
}

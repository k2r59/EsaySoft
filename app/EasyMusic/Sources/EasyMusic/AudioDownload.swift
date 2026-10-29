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
                    status: (String) -> Void = { _ in }) async throws -> (Track, String) {
        var attempted = Set<String>()
        var lastFailure: Error?
        if !target.isCatalog {
            attempted.insert(target.url)
            do { return (target, try await transfer(target, preferred)) }
            catch {
                if let failure = error as? AudioFailure, !failure.canTryAnotherSource { throw failure }
                lastFailure = error
            }
        }
        // YouTube first for catalogue tracks. If the requested source failed, try the other service first.
        let services = target.source == "YouTube" ? ["SoundCloud", "YouTube"] : ["YouTube", "SoundCloud"]
        for service in services {
            status(lastFailure == nil ? "Recherche audio sur \(service)…" : "Autre source audio : \(service)…")
            let candidates: [Track]
            do { candidates = try await search(target.artist + " " + Matching.titleForSearch(target.title), service) }
            catch { lastFailure = error; continue }
            let ranked = candidates.filter { !$0.isCatalog && Matching.score($0, for: target) >= 0.85 }
                .sorted { Matching.score($0, for: target) > Matching.score($1, for: target) }
            var count = 0
            for candidate in ranked where attempted.insert(candidate.url).inserted {
                guard count < 2 else { break }; count += 1
                do { return (candidate, try await transfer(candidate, nil)) }
                catch {
                    if let failure = error as? AudioFailure, !failure.canTryAnotherSource { throw failure }
                    lastFailure = error
                }
            }
        }
        throw MusicError.message("Aucune version audio accessible et suffisamment proche pour « \(target.title) ». Vous pouvez réessayer plus tard.")
    }

    static func transfer(_ source: Track, format: String?, folder: URL, export: String,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        // Serialize identical URLs only: two playlist entries must never write the same file together.
        await DownloadFileLock.shared.acquire(source.url)
        do {
            var args = Engine.downloadArguments(track: source, format: format, folder: folder)
            if export != "original", let ffmpeg = Engine.executable("ffmpeg") {
                args.insert(contentsOf: ["--ffmpeg-location", URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path,
                    "-x", "--audio-format", export, "--audio-quality", "0", "--embed-metadata", "--embed-thumbnail"], at: 0)
            }
            let output = try await Engine.run(args, timeout: 900) { output in
                if let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("PROGRESS:") }),
                   let value = Double(line.dropFirst(9).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                    progress(min(1, max(0, value / 100)))
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

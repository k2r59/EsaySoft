import Foundation

extension Engine {
    /// Local conversion only. Never invokes a shell or changes the original file.
    static func convert(_ input: URL, to output: URL, title: String, artist: String, lossless: Bool = false) async throws {
        guard let ffmpeg = executable("ffmpeg") else { throw MusicError.message("FFmpeg est nécessaire pour préparer ce format. Choisissez MP3 ou M4A au téléchargement, ou installez FFmpeg.") }
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-i", input.path, "-map", "0:a:0", "-vn",
                                 "-c:a", lossless ? "pcm_s16le" : "libmp3lame"]
                + (lossless ? [] : ["-q:a", "0"])
                + ["-metadata", "title=\(title)", "-metadata", "artist=\(artist)", output.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let start = Date()
            while process.isRunning {
                if Date().timeIntervalSince(start) > 300 { process.terminate(); throw MusicError.message("La conversion a dépassé le délai prévu.") }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: output)
                throw MusicError.message("Impossible de convertir \(input.lastPathComponent). Le fichier original est conservé.")
            }
        }.value
    }
}

enum Transfer {
    static func safeName(_ raw: String) -> String {
        let cleaned = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t").union(.controlCharacters)).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "Playlist" : cleaned).prefix(100))
    }
    static func export(_ tracks: [LocalTrack], name: String, into parent: URL) async throws -> URL {
        // A unique subdirectory avoids overwriting any pre-existing user file.
        let target = parent.appendingPathComponent(safeName(name) + " - " + UUID().uuidString.prefix(8), isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var m3u = "#EXTM3U\n"
        var completed = 0
        do {
            for (index, track) in tracks.enumerated() {
                let input = URL(fileURLWithPath: track.path)
                let compatible = ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "caf"].contains(input.pathExtension.lowercased())
                let filename = String(format: "%03d", index + 1) + " - " + safeName(track.track.artist + " - " + track.track.title) + "." + (compatible ? input.pathExtension : "mp3")
                let output = target.appendingPathComponent(filename)
                if compatible { try FileManager.default.copyItem(at: input, to: output) }
                else { try await Engine.convert(input, to: output, title: track.track.title, artist: track.track.artist) }
                m3u += "#EXTINF:\(Int(track.track.duration ?? -1)),\(safeName(track.track.artist)) - \(safeName(track.track.title))\n\(filename)\n"
                completed += 1
            }
            try m3u.write(to: target.appendingPathComponent("playlist.m3u8"), atomically: true, encoding: .utf8)
        } catch {
            throw MusicError.message("Export partiel : \(completed)/\(tracks.count) fichiers préparés dans \(target.path). \(error.localizedDescription)")
        }
        return target
    }
}

import Foundation

enum AudioMetadata {
    static func bitrate(_ url: URL) async -> Double? {
        guard let binary = Engine.executable("ffprobe") else { return nil }
        return await Task.detached {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=bit_rate:format=bit_rate", "-of", "json", url.path]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let deadline = Date().addingTimeInterval(15)
                while process.isRunning {
                    if Date() > deadline { process.terminate(); return nil }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                guard process.terminationStatus == 0 else { return nil }
                return parse(pipe.fileHandleForReading.readDataToEndOfFile())
            } catch { return nil }
        }.value
    }
    static func parse(_ data: Data) -> Double? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let streams = object["streams"] as? [[String: Any]]
        let format = object["format"] as? [String: Any]
        for raw in [streams?.first?["bit_rate"], format?["bit_rate"]] {
            let number = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
            if let number, number.isFinite, number > 0 { return number / 1000 }
        }
        return nil
    }
}

extension MusicStore {
    func refreshLocalBitrates() async {
        for local in library.tracks where local.bitrateKbps == nil && !checkedBitrates.contains(local.id) {
            checkedBitrates.insert(local.id)
            if let value = await AudioMetadata.bitrate(URL(fileURLWithPath: local.path)),
               let index = library.tracks.firstIndex(where: { $0.id == local.id && $0.path == local.path }) {
                library.tracks[index].bitrateKbps = value; save()
            }
        }
    }
    func canPreview(_ track: Track) -> Bool {
        downloaded(track) != nil || !(track.preview ?? "").isEmpty || !track.isCatalog
    }
}

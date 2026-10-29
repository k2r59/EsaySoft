import XCTest
@testable import EasyMusic

final class DJMetadataIntegrationTests: XCTestCase {
    func testPublicDeezerBPMRequiresNoRemoteAudioAnalysis() async throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Réseau désactivé") }
        let track = Track(id: "deezer:118313368", title: "Soushkin (7 Inch Edit)", artist: "Dream Your Dream", duration: 231,
                          url: "https://www.deezer.com/track/118313368", source: "Deezer", isCatalog: true)
        let value = try await DJMetadata().info(for: track, localPath: nil)
        let bpm = try XCTUnwrap(value.bpm)
        XCTAssertTrue(bpm.isFinite); XCTAssertGreaterThan(bpm, 0)
        XCTAssertEqual(value.bpmSource, "Deezer")
        XCTAssertNil(value.key); XCTAssertNil(value.keySource)
        print("DJ_METADATA_QA Soushkin : \(bpm) BPM déclarés par Deezer, aucune analyse distante")
    }

    func testRealLocalPipelineAndCacheInvalidationWithoutWritingAnalysisFiles() async throws {
        XCTAssertNotNil(Engine.executable("ffprobe"), "Le moteur embarqué doit être disponible")
        XCTAssertNotNil(Engine.executable("ffmpeg"), "Le moteur embarqué doit être disponible")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyMusic-DJ-QA-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("progression.wav")
        let rate = 22050.0, frames = Int(rate * 24)
        let chords = [[60, 64, 67], [53, 57, 60], [55, 59, 62]]
        let samples = (0..<frames).map { index -> Float in
            let time = Double(index) / rate, position = time.truncatingRemainder(dividingBy: 2)
            let chord = chords[position < 1.2 ? 0 : position < 1.6 ? 1 : 2]
            return Float(chord.enumerated().reduce(0.0) { sum, item in
                let frequency = 440 * pow(2, Double(item.element - 69) / 12)
                return sum + (item.offset == 0 ? 0.25 : 0.18) * sin(2 * .pi * frequency * time)
            })
        }
        let original = wave(samples)
        try original.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10_000.1)], ofItemAtPath: file.path)
        let track = Track(id: "qa-local-dj", title: "Progression synthétique", artist: "Fixture QA", duration: 24, url: file.absoluteString, source: "Test")
        let analyzer = DJMetadata(), started = Date()
        let value = try await analyzer.info(for: track, localPath: file.path)
        XCTAssertEqual(value.key?.camelot, "8B")
        XCTAssertEqual(value.keySource, "Estimation · audio")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["progression.wav"])
        XCTAssertEqual(try Data(contentsOf: file), original, "L’analyse ne doit pas modifier le morceau")
        let cached = try await analyzer.info(for: track, localPath: file.path)
        XCTAssertEqual(cached.key, value.key)

        // Same file size and same displayed second: a subsecond mtime change still invalidates the result.
        let silent = wave([Float](repeating: 0, count: frames))
        XCTAssertEqual(silent.count, original.count)
        try silent.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10_000.2)], ofItemAtPath: file.path)
        let replacement = try await analyzer.info(for: track, localPath: file.path)
        XCTAssertNil(replacement.key, "Ne pas réutiliser la tonalité du fichier remplacé")
        XCTAssertNil(replacement.bpm)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["progression.wav"])
        print("DJ_METADATA_QA FFprobe+FFmpeg+DSP : Do majeur 8B, cache invalidé sur mtime, \(Date().timeIntervalSince(started))s, aucun fichier d’analyse")
    }

    private func wave(_ samples: [Float]) -> Data {
        func word(_ value: UInt16) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
        func long(_ value: UInt32) -> [UInt8] { word(UInt16(value & 65535)) + word(UInt16(value >> 16)) }
        let length = UInt32(samples.count * 2)
        var bytes = Array("RIFF".utf8) + long(length + 36) + Array("WAVEfmt ".utf8) + long(16)
        bytes += word(1) + word(1) + long(22050) + long(44100) + word(2) + word(16)
        bytes += Array("data".utf8) + long(length)
        bytes.reserveCapacity(Int(length) + 44)
        for sample in samples {
            let integer = Int16(max(-32768, min(32767, Int((sample * 32767).rounded()))))
            bytes += word(UInt16(bitPattern: integer))
        }
        return Data(bytes)
    }
}

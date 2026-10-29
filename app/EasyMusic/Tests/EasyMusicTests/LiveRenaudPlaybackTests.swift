import XCTest
import AVFoundation
@testable import EasyMusic

final class LiveRenaudPlaybackTests: XCTestCase {
    func testReportedRenaudTitleResolvesDownloadsAndProducesPlayableAudio() async throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_RENAUD_TEST"] == "1" else { throw XCTSkip("Activer EASYMUSIC_RENAUD_TEST=1 pour le contrôle audio du titre signalé") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyMusic-Renaud-QA-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try await Engine.deezer("Renaud La ballade nord-irlandaise")
        let target = try XCTUnwrap(found.first { $0.artist == "Renaud" && $0.title.localizedCaseInsensitiveContains("ballade nord") && !$0.title.localizedCaseInsensitiveContains("live") })
        let result = try await AudioDownload.run(target: target, preferred: nil,
            search: { query, service in try await Engine.search(query, source: service, count: 5) },
            transfer: { source, format in try await AudioDownload.transfer(source, format: format, folder: root, export: "original", progress: { _ in }) })
        XCTAssertGreaterThanOrEqual(Matching.score(result.0, for: target), 0.85)
        let input = URL(fileURLWithPath: result.1)
        let bitrate = await AudioMetadata.bitrate(input)
        XCTAssertNotNil(bitrate)
        let playable: URL
        if ["webm", "opus", "ogg"].contains(input.pathExtension.lowercased()) {
            playable = root.appendingPathComponent("playback.wav")
            try await Engine.convert(input, to: playable, title: target.title, artist: target.artist, lossless: true)
        } else { playable = input }
        let asset = AVURLAsset(url: playable)
        let isPlayable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertTrue(isPlayable)
        XCTAssertFalse(audio.isEmpty)
        XCTAssertTrue(video.isEmpty)
        XCTAssertGreaterThan(duration, 30)
        if let expected = target.duration { XCTAssertLessThan(abs(duration - expected), 20) }
        print("Renaud QA : \(target.title) | \(result.0.source) | \(result.0.title) | \(duration)s | audio uniquement")
    }
}

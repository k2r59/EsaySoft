import XCTest
import AVFoundation
@testable import EasyMusic

/// Explicitly requested diagnostic. Fixtures and downloads stay outside the user's library.
final class PlaylistRecoveryLiveTests: XCTestCase {
    func testRequestedPlaylistMissingRecordingsDownloadAsCompleteAudio() async throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_PLAYLIST_RECOVERY"] == "1" else {
            throw XCTSkip("Activer EASYMUSIC_PLAYLIST_RECOVERY=1 pour le diagnostic demandé de la playlist")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".tools/playlist-061")
        let run = root.appendingPathComponent("run-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        let requestedIDs = ["spotify:5IOBAfIeu5xwLqhFeXoZhr", "spotify:5H0oTqgMq0NgvX4FnZXRr4",
                            "spotify:6gjIGTrNOaf09o4Ps8b1KM", "spotify:07GkRpJrQwPTEikq485Pdd", "spotify:160VBYGVUp5XIcoRwtOKNW"]
        let playlist = try await PlaylistImport.load("https://open.spotify.com/playlist/2Jp2pyC1epBBstxsmh7NuH")
        print("PLAYLIST_RECOVERY import réel : \(playlist.name), \(playlist.tracks.count) titres exposés")
        XCTAssertEqual(playlist.tracks.count, 61)
        var report: [[String: Any]] = []
        for (index, id) in requestedIDs.enumerated() {
            let started = Date()
            let target = try XCTUnwrap(playlist.tracks.first { $0.id == id })
            let folder = run.appendingPathComponent("audio-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var entry: [String: Any] = ["target": target.title, "artist": target.artist, "id": id, "expectedDuration": target.duration ?? 0]
            var searches: [[String: Any]] = []
            var transferErrors: [[String: String]] = []
            var inspections: [[String: Any]] = []
            do {
                let result = try await AudioDownload.run(target: target, preferred: nil,
                    search: { query, service in
                        let candidates = try await Engine.search(query, source: service, count: 5)
                        searches.append(["service": service, "query": query, "candidates": candidates.map {
                            ["title": $0.title, "artist": $0.artist, "creditedArtist": $0.creditedArtist ?? "", "duration": $0.duration ?? 0,
                             "url": $0.url, "score": Matching.score($0, for: target)] as [String: Any]
                        }])
                        return candidates
                    }, transfer: { source, format in
                        print("PLAYLIST_RECOVERY transfert : \(target.title) → \(source.source) : \(source.title)")
                        do { return try await AudioDownload.transfer(source, format: format, folder: folder, export: "m4a", progress: { _ in }) }
                        catch {
                            transferErrors.append(["url": source.url, "error": error.localizedDescription])
                            throw error
                        }
                    }, inspect: { candidate in
                        let start = Date()
                        do {
                            let enriched = try await AudioDownload.inspectCandidate(candidate)
                            inspections.append(["url": candidate.url, "seconds": Date().timeIntervalSince(start), "title": enriched?.title ?? "", "artist": enriched?.artist ?? ""])
                            return enriched
                        } catch {
                            inspections.append(["url": candidate.url, "seconds": Date().timeIntervalSince(start), "error": error.localizedDescription])
                            throw error
                        }
                    })
                let asset = AVURLAsset(url: URL(fileURLWithPath: result.1))
                let duration = try await asset.load(.duration).seconds
                let audio = try await asset.loadTracks(withMediaType: .audio)
                let video = try await asset.loadTracks(withMediaType: .video)
                let playable = try await asset.load(.isPlayable)
                let metadata = try await asset.load(.commonMetadata)
                let cover = metadata.first { $0.commonKey == .commonKeyArtwork }
                let coverData = try await cover?.load(.dataValue)
                let hasJPEGArtwork = coverData?.starts(with: [0xff, 0xd8]) == true
                XCTAssertTrue(playable); XCTAssertFalse(audio.isEmpty); XCTAssertTrue(video.isEmpty)
                XCTAssertGreaterThan(duration, 40)
                XCTAssertLessThan(abs(duration - (target.duration ?? duration)), 20)
                XCTAssertGreaterThanOrEqual(Matching.score(result.0, for: target), 0.85)
                XCTAssertTrue(hasJPEGArtwork, "La pochette JPEG doit être intégrée avec le FFmpeg distribué")
                entry["sourceURL"] = result.0.url; entry["sourceTitle"] = result.0.title; entry["sourceArtist"] = result.0.artist
                entry["duration"] = duration; entry["audioTracks"] = audio.count; entry["videoTracks"] = video.count
                entry["jpegArtwork"] = hasJPEGArtwork
                entry["path"] = result.1; entry["recovered"] = playable && !audio.isEmpty && video.isEmpty && abs(duration - (target.duration ?? duration)) < 20
                entry["bytes"] = try URL(fileURLWithPath: result.1).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                print("PLAYLIST_RECOVERY OK : \(target.title) | \(duration)s | \(result.0.url)")
            } catch {
                entry["recovered"] = false; entry["error"] = error.localizedDescription
                print("PLAYLIST_RECOVERY ÉCHEC : \(target.title) | \(error.localizedDescription)")
            }
            entry["searches"] = searches; entry["transferErrors"] = transferErrors; entry["inspections"] = inspections
            entry["elapsedSeconds"] = Date().timeIntervalSince(started); report.append(entry)
            let output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: root.appendingPathComponent("recovery-report.json"))
            try output.write(to: run.appendingPathComponent("report.json"))
        }
        for entry in report {
            if entry["id"] as? String == "spotify:160VBYGVUp5XIcoRwtOKNW" {
                // The available official upload does not identify the Medley version; omission is coherent.
                XCTAssertEqual(entry["recovered"] as? Bool, false, "Une version Medley ambiguë ne doit pas être assimilée à l’original")
            } else {
                XCTAssertEqual(entry["recovered"] as? Bool, true, "Fichier complet attendu pour \(entry["target"] ?? "")")
            }
        }
    }
}

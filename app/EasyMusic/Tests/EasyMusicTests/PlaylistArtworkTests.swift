import XCTest
import AppKit
@testable import EasyMusic

@MainActor final class PlaylistArtworkTests: XCTestCase {
    func testDefaultUsesFirstTrackAndCustomCoverSurvivesSyncAndReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("library.json")
        let store = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        let a = Track(id: "a", title: "A", artist: "Artist", artwork: "https://example.com/a.jpg", url: "https://example.com/a", source: "Test")
        var b = a; b.id = "b"; b.artwork = "https://example.com/b.jpg"
        let imported = ImportedPlaylist(name: "Playlist", sourceURL: "https://www.deezer.com/playlist/123", tracks: [a, b])
        store.acceptImport(imported)
        let playlist = try XCTUnwrap(store.currentPlaylist)
        XCTAssertEqual(store.defaultArtwork(for: playlist), a.artwork)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let input = root.appendingPathComponent("cover.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: input)
        try store.setArtwork(for: playlist.id, from: input)
        let copied = try XCTUnwrap(store.currentPlaylist?.artworkPath)
        XCTAssertNotEqual(copied, input.path)
        XCTAssertNotNil(NSImage(contentsOfFile: copied))
        var changed = imported; changed.tracks = [b, a]
        await store.refreshPlaylist(playlist.id, apply: true, load: { _ in changed })
        XCTAssertEqual(store.currentPlaylist?.artworkPath, copied)
        XCTAssertEqual(store.defaultArtwork(for: try XCTUnwrap(store.currentPlaylist)), b.artwork)
        let reloaded = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        XCTAssertEqual(reloaded.library.playlists.first?.artworkPath, copied)
        store.resetArtwork(for: playlist.id)
        XCTAssertNil(store.currentPlaylist?.artworkPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }
}

actor DownloadWorkerProbe {
    var active = 0, maximum = 0, calls = 0
    func perform(_ track: Track, folder: URL) async throws -> (Track, String) {
        active += 1; calls += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        if track.id == "bad" { throw AudioFailure.localFile }
        let path = folder.appendingPathComponent(track.id + ".m4a")
        try Data([1]).write(to: path)
        return (track, path.path)
    }
}

@MainActor final class DownloadQueueTests: XCTestCase {
    func testTwoConcurrentDownloadsContinueAfterFailureAndRejectDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        let probe = DownloadWorkerProbe()
        store.downloadWorker = { track, _, _, folder in try await probe.perform(track, folder: folder) }
        let tracks = ["bad", "second", "third"].map { Track(id: $0, title: $0, artist: "Artist", url: "https://example.com/\($0)", source: "Test") }
        tracks.forEach { store.enqueue($0) }; store.enqueue(tracks[0])
        XCTAssertEqual(store.activeDownloads.count, 2)
        XCTAssertEqual(store.pending.count, 1)
        for _ in 0..<200 {
            if store.activeDownloads.isEmpty && store.pending.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(store.activeDownloads.isEmpty)
        XCTAssertEqual(store.library.tracks.count, 2)
        XCTAssertNotNil(store.downloadErrors["bad"])
        let maximum = await probe.maximum, calls = await probe.calls
        XCTAssertEqual(maximum, 2); XCTAssertEqual(calls, 3)
    }
}

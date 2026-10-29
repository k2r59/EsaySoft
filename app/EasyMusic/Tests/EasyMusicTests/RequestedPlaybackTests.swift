import XCTest
@testable import EasyMusic

@MainActor final class RequestedPlaybackTests: XCTestCase {
    func track(_ id: String) -> Track { Track(id: id, title: id, artist: "Artist", duration: 120, url: "https://example.com/\(id)", source: "Test") }
    func testRemotePlayDownloadsOnceAndStartsWhenReady() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        var transfers = 0
        store.downloadWorker = { track, _, _, folder in
            transfers += 1
            try await Task.sleep(nanoseconds: 25_000_000)
            let file = folder.appendingPathComponent("test.wav"); try Data([1]).write(to: file)
            return (track, file.path)
        }
        let song = track("one"); store.requestPlayback(song)
        XCTAssertEqual(store.requestedPlayback?.id, song.id)
        for _ in 0..<100 where store.playing == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.playing?.track.id, song.id)
        XCTAssertNil(store.requestedPlayback)
        XCTAssertEqual(transfers, 1)
        store.requestPlayback(song)
        XCTAssertEqual(transfers, 1)
    }
    func testCancelAutoplayKeepsDownloadWithoutStartingAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        store.downloadWorker = { track, _, _, folder in
            try await Task.sleep(nanoseconds: 30_000_000)
            let file = folder.appendingPathComponent("test.wav"); try Data([1]).write(to: file)
            return (track, file.path)
        }
        let song = track("one"); store.requestPlayback(song); store.requestPlayback(song)
        XCTAssertNil(store.requestedPlayback)
        for _ in 0..<100 where !store.activeDownloads.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(store.playing)
        XCTAssertNotNil(store.downloaded(song))
    }
    func testLatestRequestedTrackWinsWhenTransfersFinishOutOfOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        store.downloadWorker = { track, _, _, folder in
            try await Task.sleep(nanoseconds: track.id == "first" ? 80_000_000 : 20_000_000)
            let file = folder.appendingPathComponent(track.id + ".wav"); try Data([1]).write(to: file)
            return (track, file.path)
        }
        store.requestPlayback(track("first")); store.requestPlayback(track("last"))
        for _ in 0..<100 where !store.activeDownloads.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.playing?.track.id, "last")
        XCTAssertNil(store.requestedPlayback)
    }
    func testFailureClearsLoadingAndExplainsError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        store.downloadWorker = { _, _, _, _ in throw AudioFailure.network }
        store.requestPlayback(track("unavailable"))
        for _ in 0..<100 where !store.activeDownloads.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(store.requestedPlayback); XCTAssertNil(store.playing)
        XCTAssertNotNil(store.downloadErrors["unavailable"])
    }
    func testAttributionDoesNotPreventRenaudMatchButVersionsRemainProtected() {
        let title = "La ballade nord-irlandaise (Sur les motifs de \"Water Is Deep\")"
        let target = Track(id: "catalog", title: title, artist: "Renaud", duration: 220, url: "https://example.com/1", source: "Deezer", isCatalog: true)
        var candidate = Track(id: "audio", title: "Renaud - La ballade nord-irlandaise", artist: "Renaud", duration: 220, url: "https://example.com/2", source: "YouTube")
        XCTAssertEqual(Matching.titleForSearch(title), "La ballade nord-irlandaise")
        XCTAssertGreaterThanOrEqual(Matching.score(candidate, for: target), 0.85)
        candidate.title += " live cover"
        XCTAssertLessThan(Matching.score(candidate, for: target), 0.85)
        XCTAssertEqual(Matching.titleForSearch("Song (Live Remix)"), "Song (Live Remix)")
    }
}

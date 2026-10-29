import XCTest
import AVFoundation
@testable import EasyMusic

@MainActor final class RequestedPlaybackTests: XCTestCase {
    func track(_ id: String) -> Track {
        Track(id: id, title: id, artist: "Artist", duration: 60, url: "https://example.com/\(id)", source: "Test")
    }
    func fixture(observe: Bool = false) throws -> (MusicStore, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyMusic-Streaming-QA-" + UUID().uuidString)
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("stream-fixture.wav")
        var bytes = Data()
        func text(_ text: String) { bytes.append(contentsOf: text.utf8) }
        func word(_ n: UInt16) { var value = n.littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        func dword(_ n: UInt32) { var value = n.littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        let size: UInt32 = 8000 * 2 * 60
        text("RIFF"); dword(size + 36); text("WAVEfmt "); dword(16); word(1); word(1)
        dword(8000); dword(16000); word(2); word(16); text("data"); dword(size)
        bytes.append(Data(repeating: 0, count: Int(size))); try bytes.write(to: audio)
        return (MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: music, observePlayback: observe), root, audio)
    }
    func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(predicate(), "État attendu absent après deux secondes", file: file, line: line)
    }
    func testRemotePlayStreamsWithoutDownloadingOrSavingToLibrary() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        var resolutions = 0, transfers = 0
        store.streamResolver = { song, _ in resolutions += 1; return AudioStream(url: audio, source: song) }
        store.downloadWorker = { _, _, _, _ in transfers += 1; throw AudioFailure.network }
        let song = track("one")
        store.requestPlayback(song)
        try await eventually { store.streaming?.id == song.id }
        XCTAssertNil(store.requestedPlayback); XCTAssertNil(store.playing); XCTAssertNil(store.previewing)
        XCTAssertEqual(store.currentTrack?.id, song.id)
        XCTAssertEqual(resolutions, 1); XCTAssertEqual(transfers, 0)
        XCTAssertTrue(store.library.tracks.isEmpty); XCTAssertTrue(store.pending.isEmpty); XCTAssertTrue(store.activeDownloads.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.folder.path).isEmpty)
        store.requestPlayback(song)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(resolutions, 1, "Pause ne doit pas résoudre à nouveau le flux")
    }
    func testCancelStreamingIgnoresLateResolverWithoutDownloading() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        store.streamResolver = { song, _ in
            try? await Task.sleep(nanoseconds: 60_000_000)
            return AudioStream(url: audio, source: song)
        }
        let song = track("one")
        store.requestPlayback(song)
        await Task.yield()
        store.requestPlayback(song)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(store.requestedPlayback); XCTAssertNil(store.streaming); XCTAssertNil(store.playing)
        XCTAssertNil(store.player.currentItem); XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.activeDownloads.isEmpty); XCTAssertTrue(store.library.tracks.isEmpty)
    }
    func testLatestRequestedTrackWinsWhenResolversFinishOutOfOrder() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        store.streamResolver = { song, _ in
            try? await Task.sleep(nanoseconds: song.id == "first" ? 100_000_000 : 10_000_000)
            return AudioStream(url: audio, source: song)
        }
        store.requestPlayback(track("first")); await Task.yield()
        store.requestPlayback(track("last"))
        try await eventually { store.streaming?.id == "last" }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.currentTrack?.id, "last"); XCTAssertNil(store.requestedPlayback)
        XCTAssertTrue(store.library.tracks.isEmpty)
    }
    func testStreamFailureClearsLoadingAndDoesNotBecomeADownloadError() async throws {
        let (store, root, _) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        store.streamResolver = { _, _ in throw AudioFailure.network }
        store.requestPlayback(track("unavailable"))
        try await eventually { store.requestedPlayback == nil }
        XCTAssertNil(store.streaming); XCTAssertNil(store.playing); XCTAssertFalse(store.isPlaying)
        XCTAssertNotNil(store.notice); XCTAssertTrue(store.downloadErrors.isEmpty)
        XCTAssertTrue(store.activeDownloads.isEmpty); XCTAssertTrue(store.library.tracks.isEmpty)
    }
    func testExistingLocalFileHasPriorityOverStreamResolution() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let song = track("local"), local = LocalTrack(track: track("local"), path: audio.path)
        store.library.tracks = [local]
        var resolutions = 0
        store.streamResolver = { _, _ in resolutions += 1; throw AudioFailure.network }
        store.requestPlayback(song)
        try await eventually { store.playing?.id == local.id && store.isPlaying }
        XCTAssertEqual(store.currentTrack?.id, song.id); XCTAssertNil(store.streaming); XCTAssertEqual(resolutions, 0)
        store.requestPlayback(song)
        XCTAssertFalse(store.isPlaying); XCTAssertEqual(resolutions, 0)
    }
    func testExplicitDownloadDuringStreamingDoesNotReplacePlayerItem() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let song = track("simultaneous")
        store.streamResolver = { source, _ in AudioStream(url: audio, source: source) }
        var transfers = 0
        store.downloadWorker = { source, _, _, folder in
            transfers += 1
            let output = folder.appendingPathComponent("download.wav")
            try FileManager.default.copyItem(at: audio, to: output)
            return (source, output.path)
        }
        store.requestPlayback(song)
        try await eventually { store.streaming?.id == song.id && store.player.currentItem != nil }
        let item = try XCTUnwrap(store.player.currentItem)
        store.enqueue(song)
        try await eventually { store.downloaded(song) != nil && store.activeDownloads.isEmpty }
        XCTAssertEqual(transfers, 1); XCTAssertEqual(store.library.tracks.count, 1)
        XCTAssertTrue(store.player.currentItem === item, "Le téléchargement explicite ne doit pas relancer le lecteur")
        XCTAssertEqual(store.streaming?.id, song.id); XCTAssertNil(store.playing)
    }
    func testMixedQueueNavigatesAndShuffleRestoresOriginalOrder() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let first = track("first"), middle = track("middle"), last = track("last")
        store.library.tracks = [LocalTrack(track: middle, path: audio.path)]
        store.section = "search"; store.results = [first, middle, last]
        store.streamResolver = { source, _ in AudioStream(url: audio, source: source) }
        store.requestPlayback(first)
        try await eventually { store.streaming?.id == first.id }
        XCTAssertEqual(store.playbackQueue.map(\.id), [first.id, middle.id, last.id])
        store.toggleShuffle(); store.toggleShuffle()
        XCTAssertEqual(store.playbackQueue.map(\.id), [first.id, middle.id, last.id])
        store.next(); try await eventually { store.playing?.track.id == middle.id }
        store.next(); try await eventually { store.streaming?.id == last.id }
        store.repeatMode = 0; store.playbackEnded()
        XCTAssertFalse(store.isPlaying, "Fin de file sans répétition doit arrêter la lecture")
        store.repeatMode = 1; store.playbackEnded()
        try await eventually { store.streaming?.id == first.id }
    }
    func testPreviewCancelsPendingStreamAndLateResultCannotReplaceIt() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let sample = track("sample")
        store.library.tracks = [LocalTrack(track: sample, path: audio.path)]
        store.streamResolver = { source, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return AudioStream(url: audio, source: source)
        }
        store.requestPlayback(track("pending")); await Task.yield(); store.preview(sample)
        try await eventually { store.previewing?.id == sample.id }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.currentTrack?.id, sample.id); XCTAssertNil(store.streaming); XCTAssertNil(store.requestedPlayback)
    }
    func testFullStreamContinuesBeyondThirtySecondsButPreviewStops() async throws {
        let (store, root, audio) = try fixture(observe: true)
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let song = track("full")
        store.streamResolver = { source, _ in AudioStream(url: audio, source: source) }
        store.requestPlayback(song)
        try await eventually { store.streaming?.id == song.id && store.player.currentItem?.status == .readyToPlay }
        store.seek(39)
        try await eventually { store.position > 39.2 && store.player.timeControlStatus == .playing }
        XCTAssertTrue(store.isPlaying); XCTAssertGreaterThan(store.playerDuration, 30)
        store.library.tracks = [LocalTrack(track: song, path: audio.path)]
        store.preview(song)
        try await eventually { store.previewing?.id == song.id && store.player.currentItem?.status == .readyToPlay }
        try await eventually { store.position > 0.2 && store.position < 3 && store.isPlaying && store.player.timeControlStatus == .playing }
        store.seek(30)
        try await eventually { !store.isPlaying && store.position >= 30 }
        XCTAssertNil(store.streaming); XCTAssertLessThanOrEqual(store.playerDuration, 30)
    }
    func testEndNotificationForAnOldItemDoesNotAdvanceCurrentStream() async throws {
        let (store, root, audio) = try fixture(observe: true)
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let first = track("first"), last = track("last")
        store.section = "search"; store.results = [first, last]
        store.streamResolver = { source, _ in AudioStream(url: audio, source: source) }
        store.requestPlayback(first)
        try await eventually { store.streaming?.id == first.id && store.player.currentItem != nil }
        let obsolete = AVPlayerItem(url: audio)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: obsolete)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(store.currentTrack?.id, first.id, "Un item obsolète ne doit pas déclencher Suivant")
    }
    func testPlaybackFailureExcludesSourcesAndStopsAfterThreeAttempts() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let song = track("fallback")
        var exclusions: [Set<String>] = []
        store.streamResolver = { source, excluded in
            exclusions.append(excluded)
            var candidate = source
            candidate.url = "https://example.com/source-\(exclusions.count)"
            return AudioStream(url: audio, source: candidate)
        }
        store.requestPlayback(song)
        try await eventually { store.player.currentItem != nil }
        for attempt in 1...3 {
            let failed = try XCTUnwrap(store.player.currentItem)
            store.playbackFailed(failed)
            if attempt < 3 { try await eventually { store.player.currentItem != nil && store.player.currentItem !== failed } }
        }
        XCTAssertEqual(exclusions.count, 3)
        XCTAssertEqual(exclusions[1], ["https://example.com/source-1"])
        XCTAssertEqual(exclusions[2], ["https://example.com/source-1", "https://example.com/source-2"])
        XCTAssertNil(store.player.currentItem); XCTAssertNil(store.requestedPlayback); XCTAssertNil(store.streaming)
        XCTAssertFalse(store.isPlaying); XCTAssertNotNil(store.notice)
        XCTAssertTrue(store.downloadErrors.isEmpty); XCTAssertTrue(store.library.tracks.isEmpty)
    }
    func testPlaybackFailureForOldItemCannotInterruptNewStream() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        var resolutions = 0
        store.streamResolver = { source, _ in resolutions += 1; return AudioStream(url: audio, source: source) }
        store.requestPlayback(track("first"))
        try await eventually { store.player.currentItem != nil }
        let old = try XCTUnwrap(store.player.currentItem)
        store.requestPlayback(track("last"))
        try await eventually { store.streaming?.id == "last" }
        let current = try XCTUnwrap(store.player.currentItem)
        store.playbackFailed(old)
        XCTAssertTrue(store.player.currentItem === current)
        XCTAssertEqual(store.currentTrack?.id, "last"); XCTAssertEqual(resolutions, 2)
    }
    func testNextAtEndOfQueueCancelsPendingStreamWithoutLateAutoplay() async throws {
        let (store, root, audio) = try fixture()
        defer { store.player.pause(); try? FileManager.default.removeItem(at: root) }
        let song = track("only")
        store.section = "search"; store.results = [song]
        store.streamResolver = { source, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return AudioStream(url: audio, source: source)
        }
        store.requestPlayback(song); await Task.yield()
        XCTAssertEqual(store.playbackQueue.count, 1)
        store.next()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(store.requestedPlayback); XCTAssertNil(store.streaming); XCTAssertNil(store.player.currentItem)
        XCTAssertFalse(store.isPlaying)
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

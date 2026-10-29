import XCTest
import AVFoundation
@testable import EasyMusic

@MainActor final class PrefetchPlaybackTests: XCTestCase {
    private struct Fixture {
        let store: MusicStore
        let root: URL
        let audio: URL
        let local: LocalTrack
        let remotes: [Track]
    }

    private func fixture(remoteCount: Int = 1) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyMusic-Prefetch-QA-" + UUID().uuidString)
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let audio = music.appendingPathComponent("local.wav")
        var bytes = Data()
        func text(_ value: String) { bytes.append(contentsOf: value.utf8) }
        func word(_ number: UInt16) { var value = number.littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        func dword(_ number: UInt32) { var value = number.littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        let size: UInt32 = 8_000 * 2 * 60
        text("RIFF"); dword(size + 36); text("WAVEfmt "); dword(16); word(1); word(1)
        dword(8_000); dword(16_000); word(2); word(16); text("data"); dword(size)
        bytes.append(Data(repeating: 0, count: Int(size)))
        try bytes.write(to: audio)
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: music, observePlayback: true)
        store.player.isMuted = true
        let local = LocalTrack(track: Track(id: "local", title: "Local", artist: "QA", duration: 60,
                                            url: "https://example.com/local", source: "Local"), path: audio.path)
        let remotes = (1...remoteCount).map { index in
            Track(id: "remote-\(index)", title: "Remote \(index)", artist: "QA", duration: 60,
                  url: "https://example.com/remote-\(index)", source: "Deezer", isCatalog: true)
        }
        let playlist = Playlist(name: "Prefetch QA", importedTracks: [local.track] + remotes)
        store.library.tracks = [local]; store.library.playlists = [playlist]; store.section = playlist.id.uuidString
        // Never let a failed assertion reach a real service.
        store.streamResolver = { _, _ in throw AudioFailure.network }
        store.downloadWorker = { _, _, _, _ in XCTFail("Préparer un flux ne doit pas télécharger"); throw AudioFailure.network }
        return Fixture(store: store, root: root, audio: audio, local: local, remotes: remotes)
    }

    private func eventually(timeout: TimeInterval = 4, _ predicate: () -> Bool,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate(), "État attendu absent après \(timeout) secondes", file: file, line: line)
    }

    private func cleanup(_ fixture: Fixture) {
        fixture.store.cancelRequestedPlayback()
        try? FileManager.default.removeItem(at: fixture.root)
    }

    func testNextReusesInFlightPreparationWithoutSecondResolution() async throws {
        let f = try fixture(); defer { cleanup(f) }
        let store = f.store, remote = f.remotes[0]
        var starts = 0, foreground = 0, release = false, cancelled = false
        store.streamResolver = { song, _ in foreground += 1; return AudioStream(url: f.audio, source: song) }
        store.streamPrefetchResolver = { song in
            starts += 1
            do { while !release { try await Task.sleep(nanoseconds: 20_000_000) } }
            catch { cancelled = true; throw error }
            return AudioStream(url: f.audio, source: song)
        }
        store.requestPlayback(f.local.track)
        try await eventually { starts == 1 }
        XCTAssertEqual(store.playing?.id, f.local.id)
        XCTAssertTrue(store.isPlaying)
        store.next()
        try await eventually { store.requestedPlayback?.id == remote.id }
        XCTAssertEqual(starts, 1); XCTAssertEqual(foreground, 0); XCTAssertFalse(cancelled)
        release = true
        try await eventually { store.streaming?.id == remote.id && store.player.currentTime().seconds > 0.1 }
        XCTAssertEqual(starts, 1); XCTAssertEqual(foreground, 0); XCTAssertFalse(cancelled)
        XCTAssertEqual(store.library.tracks.map(\.id), [f.local.id])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.folder.path), ["local.wav"])
    }

    func testHoverPreparationIsSilentAndTransferredToClick() async throws {
        let f = try fixture(); defer { cleanup(f) }
        let track = f.remotes[0]
        var preparations = 0, foreground = 0, release = false, cancelled = false
        f.store.streamResolver = { song, _ in foreground += 1; return AudioStream(url: f.audio, source: song) }
        f.store.streamPrefetchResolver = { song in
            preparations += 1
            do { while !release { try await Task.sleep(nanoseconds: 20_000_000) } }
            catch { cancelled = true; throw error }
            return AudioStream(url: f.audio, source: song)
        }
        f.store.preparePlaybackIntent(track, hovering: true)
        try await eventually { preparations == 1 }
        XCTAssertNil(f.store.currentTrack); XCTAssertNil(f.store.player.currentItem)
        XCTAssertFalse(f.store.isPlaying); XCTAssertNil(f.store.requestedPlayback)
        f.store.requestPlayback(track)
        f.store.preparePlaybackIntent(track, hovering: false)
        release = true
        try await eventually { f.store.streaming?.id == track.id && f.store.player.currentTime().seconds > 0.1 }
        XCTAssertEqual(preparations, 1); XCTAssertEqual(foreground, 0); XCTAssertFalse(cancelled)
        XCTAssertEqual(f.store.library.tracks.map(\.id), [f.local.id])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.store.folder.path), ["local.wav"])
    }

    func testLeavingHoverCancelsPendingAndRunningPreparation() async throws {
        let f = try fixture(); defer { cleanup(f) }
        let track = f.remotes[0]
        var starts = 0, cancelled = false
        f.store.streamPrefetchResolver = { song in
            starts += 1
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { cancelled = true; throw error }
            return AudioStream(url: f.audio, source: song)
        }
        f.store.preparePlaybackIntent(track, hovering: true)
        f.store.preparePlaybackIntent(track, hovering: false)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(starts, 0)
        f.store.preparePlaybackIntent(track, hovering: true)
        try await eventually { starts == 1 }
        f.store.preparePlaybackIntent(track, hovering: false)
        try await eventually { cancelled }
        XCTAssertNil(f.store.currentTrack); XCTAssertNil(f.store.player.currentItem)
        XCTAssertFalse(f.store.isPlaying)
    }

    func testHoverDoesNotCompeteWithRequestedPlayback() async throws {
        let f = try fixture(remoteCount: 2); defer { cleanup(f) }
        var preparations = 0
        f.store.streamResolver = { song, _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return AudioStream(url: f.audio, source: song)
        }
        f.store.streamPrefetchResolver = { song in preparations += 1; return AudioStream(url: f.audio, source: song) }
        f.store.requestPlayback(f.remotes[0])
        f.store.preparePlaybackIntent(f.remotes[1], hovering: true)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(preparations, 0)
        XCTAssertEqual(f.store.requestedPlayback?.id, f.remotes[0].id)
    }

    func testCancellingHandoffCancelsPreparationAndIgnoresLateResult() async throws {
        let f = try fixture(); defer { cleanup(f) }
        let store = f.store
        var started = false, cancelled = false, returned = false, foreground = 0
        store.streamResolver = { song, _ in foreground += 1; return AudioStream(url: f.audio, source: song) }
        store.streamPrefetchResolver = { song in
            started = true
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { cancelled = true }
            // Simulate a resolver that still returns after cancellation.
            returned = true
            return AudioStream(url: f.audio, source: song)
        }
        store.requestPlayback(f.local.track)
        try await eventually { started }
        store.next()
        await Task.yield()
        store.cancelRequestedPlayback()
        try await eventually { cancelled && returned }
        await Task.yield()
        XCTAssertNil(store.currentTrack); XCTAssertNil(store.requestedPlayback)
        XCTAssertNil(store.player.currentItem); XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.isBuffering); XCTAssertEqual(foreground, 0)
        XCTAssertTrue(store.pending.isEmpty); XCTAssertTrue(store.activeDownloads.isEmpty)
    }

    func testFailedPreparationDoesNotInterruptCurrentTrackAndNextCanRetry() async throws {
        let f = try fixture(); defer { cleanup(f) }
        let store = f.store, remote = f.remotes[0]
        var preparationFailed = false, foreground = 0
        store.streamPrefetchResolver = { _ in preparationFailed = true; throw AudioFailure.network }
        store.streamResolver = { song, _ in foreground += 1; return AudioStream(url: f.audio, source: song) }
        store.requestPlayback(f.local.track)
        try await eventually { preparationFailed }
        XCTAssertEqual(store.playing?.id, f.local.id); XCTAssertTrue(store.isPlaying)
        XCTAssertNil(store.notice)
        store.next()
        try await eventually { store.streaming?.id == remote.id && store.player.currentTime().seconds > 0.1 }
        XCTAssertEqual(foreground, 1)
        XCTAssertNil(store.notice)
    }

    func testShufflePreparesActualNextAndRestoringOrderPreparesOriginalNext() async throws {
        let f = try fixture(remoteCount: 3); defer { cleanup(f) }
        let store = f.store
        var activePreparation: String?, starts: [String] = []
        store.streamPrefetchResolver = { song in
            starts.append(song.id); activePreparation = song.id
            do { try await Task.sleep(nanoseconds: 20_000_000_000) }
            catch { if activePreparation == song.id { activePreparation = nil }; throw error }
            return AudioStream(url: f.audio, source: song)
        }
        store.requestPlayback(f.local.track)
        try await eventually { activePreparation == f.remotes[0].id }
        store.toggleShuffle()
        let shuffledNext = try XCTUnwrap(store.playbackQueue.dropFirst().first)
        try await eventually { starts.count >= 2 && activePreparation == shuffledNext.id }
        XCTAssertEqual(store.playbackQueue.first?.id, f.local.track.id)
        store.toggleShuffle()
        try await eventually { starts.count >= 3 && activePreparation == f.remotes[0].id }
        XCTAssertEqual(store.playbackQueue.map(\.id), [f.local.track.id] + f.remotes.map(\.id))
        XCTAssertEqual(store.playing?.id, f.local.id)
        XCTAssertTrue(store.isPlaying); XCTAssertNil(store.notice)
    }

    func testPreviewDoesNotPrepareTheNextFullTrack() async throws {
        let f = try fixture(); defer { cleanup(f) }
        let store = f.store
        var preparations = 0
        store.streamPrefetchResolver = { song in preparations += 1; return AudioStream(url: f.audio, source: song) }
        store.preparePlaybackQueue(for: f.local.track)
        store.preview(f.local.track)
        try await eventually { store.previewing?.id == f.local.track.id && store.player.currentItem?.status == .readyToPlay }
        // The production preparation delay is one second; observe beyond it.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(preparations, 0)
        XCTAssertEqual(store.previewing?.id, f.local.track.id)
        XCTAssertNil(store.streaming)
    }
}

import XCTest
@testable import EasyMusic

@MainActor final class QAActionTests: XCTestCase {
    func fixture() throws -> (MusicStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyMusic-QA-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false), root)
    }
    func track(_ id: String) -> Track {
        Track(id: id, title: "Song " + id, artist: "Artist", duration: 120, url: "https://example.com/" + id, source: "Test")
    }
    func testManualRemoteAdditionSurvivesSourceSynchronization() async throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = track("original"), added = track("manual")
        let source = "https://www.deezer.com/playlist/1"
        store.acceptImport(ImportedPlaylist(name: "Imported", sourceURL: source, tracks: [original]))
        let id = try XCTUnwrap(store.currentPlaylist?.id)
        // Already queued: membership must reuse its request and not start a real network transfer.
        store.pending = [added]
        store.setMembership(added, in: id, included: true)
        await store.refreshPlaylist(id, apply: true) { _ in ImportedPlaylist(name: "Remote", sourceURL: source, tracks: [original]) }
        XCTAssertTrue(store.playlistTracks(try XCTUnwrap(store.currentPlaylist)).contains { $0.id == added.id }, "Un ajout manuel ne doit pas disparaître lors de la synchronisation")
    }
    func testRemoveLocalTrackAlsoRemovesImportedMembership() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let song = track("a"), file = root.appendingPathComponent("a.m4a")
        try Data([1]).write(to: file)
        let local = LocalTrack(track: song, path: file.path)
        store.library.tracks = [local]
        store.acceptImport(ImportedPlaylist(name: "Imported", sourceURL: "https://www.deezer.com/playlist/1", tracks: [song]))
        let id = try XCTUnwrap(store.currentPlaylist?.id)
        store.remove(local, from: id)
        XCTAssertFalse(store.contains(song, in: try XCTUnwrap(store.currentPlaylist)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testDisablingShuffleRestoresPlaylistOrder() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let locals = ["a", "b", "c"].map { LocalTrack(track: track($0), path: root.appendingPathComponent($0 + ".m4a").path) }
        for local in locals { try Data([1]).write(to: URL(fileURLWithPath: local.path)) }
        store.library.tracks = locals.reversed()
        let list = Playlist(name: "In order", trackIDs: locals.map(\.id))
        store.library.playlists = [list]; store.section = list.id.uuidString
        store.play(locals[0])
        store.toggleShuffle(); store.toggleShuffle()
        XCTAssertEqual(store.playbackQueue.map(\.id), locals.map(\.id), "Désactiver aléatoire doit restaurer l’ordre de la playlist")
    }
    func testConversionNeverDeletesPreexistingOutput() async throws {
        guard Engine.executable("ffmpeg") != nil else { throw XCTSkip("FFmpeg requis") }
        let (_, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("invalid.m4a"), output = root.appendingPathComponent("existing.mp3")
        let original = Data("keep this existing output".utf8)
        try Data([1]).write(to: input); try original.write(to: output)
        do { try await Engine.convert(input, to: output, title: "Test", artist: "Test"); XCTFail("Une sortie existante ne doit pas être remplacée") } catch {}
        XCTAssertEqual(try? Data(contentsOf: output), original, "Un échec ne doit jamais effacer une sortie préexistante")
    }
    func testSameRecordingAcrossSourcesIsNotDownloadedTwiceConcurrently() async throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = track("a")
        var alias = first; alias.id = "another-source"; alias.url = "https://example.com/other-source"; alias.source = "Other"
        store.downloadWorker = { _, _, _, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            throw AudioFailure.network
        }
        store.enqueue(first); store.enqueue(alias)
        XCTAssertEqual(store.activeDownloads.count + store.pending.count, 1, "Deux résultats du même enregistrement doivent partager le téléchargement")
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testMissingLocalFileIsNotReportedAsDownloadedAndCanRetry() async throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let song = track("missing")
        store.library.tracks = [LocalTrack(track: song, path: root.appendingPathComponent("missing.m4a").path)]
        XCTAssertNil(store.downloaded(song))
        store.downloadWorker = { _, _, _, _ in throw AudioFailure.network }
        store.enqueue(song)
        XCTAssertTrue(store.isQueued(song))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(store.isQueued(song))
        XCTAssertNotNil(store.downloadErrors[song.id])
    }
    func testBlankRenameLeavesImportedIdentityAndNameUnchanged() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let list = Playlist(name: "Keep", sourceURL: "https://www.deezer.com/playlist/1", artworkPath: "cover.png")
        store.library.playlists = [list]
        store.renamePlaylist(list.id, to: "   ")
        XCTAssertEqual(store.library.playlists[0].name, "Keep")
        XCTAssertEqual(store.library.playlists[0].sourceURL, list.sourceURL)
        XCTAssertEqual(store.library.playlists[0].artworkPath, "cover.png")
    }
    func testPartialExportReportsCountAndPreservesOriginals() async throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.m4a"); let bytes = Data([1, 2, 3]); try bytes.write(to: first)
        let items = [LocalTrack(track: track("a"), path: first.path), LocalTrack(track: track("b"), path: root.appendingPathComponent("missing.m4a").path)]
        store.library.tracks = items
        do { _ = try await Transfer.export(items, name: "Partial", into: root); XCTFail("Export doit indiquer le fichier manquant") }
        catch { XCTAssertTrue(error.localizedDescription.contains("1/2")) }
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        XCTAssertEqual(store.library.tracks.count, 2)
    }
    func testMuteRestoresPreviousVolume() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        store.volume = 0.37
        store.toggleMute(); XCTAssertEqual(store.volume, 0)
        store.toggleMute(); XCTAssertEqual(store.volume, 0.37, accuracy: 0.001)
    }

}

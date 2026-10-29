import XCTest
@testable import EasyMusic

@MainActor final class PlaylistSyncTests: XCTestCase {
    func track(_ id: String) -> Track { Track(id: id, title: id, artist: "Artist", url: "https://example.com/\(id)", source: "Test") }
    func testRenameChangeBadgeAndSyncPreserveLinkLocalNameAndFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        let link = "https://www.deezer.com/playlist/123"
        store.acceptImport(ImportedPlaylist(name: "Original", sourceURL: link, tracks: [track("a"), track("b")]))
        let id = try XCTUnwrap(store.currentPlaylist?.id)
        let file = root.appendingPathComponent("a.m4a"); try Data([1, 2]).write(to: file)
        let local = LocalTrack(track: track("a"), path: file.path); store.library.tracks = [local]
        store.renamePlaylist(id, to: "Mon nom")
        XCTAssertEqual(store.currentPlaylist?.sourceURL, link)
        let remote = ImportedPlaylist(name: "Changed remote name", sourceURL: link, tracks: [track("b"), track("c")])
        await store.refreshPlaylist(id, apply: false, load: { url in XCTAssertEqual(url, link); return remote })
        XCTAssertEqual(store.currentPlaylist?.hasRemoteChanges, true)
        XCTAssertEqual(store.currentPlaylist?.importedTracks?.map(\.id), ["a", "b"])
        await store.refreshPlaylist(id, apply: true, load: { _ in remote })
        XCTAssertEqual(store.currentPlaylist?.name, "Mon nom")
        XCTAssertEqual(store.currentPlaylist?.hasRemoteChanges, false)
        XCTAssertEqual(store.currentPlaylist?.importedTracks?.map(\.id), ["b", "c"])
        XCTAssertEqual(store.library.tracks.first?.id, local.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let restored = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        XCTAssertEqual(restored.library.playlists.first?.name, "Mon nom")
        XCTAssertEqual(restored.library.playlists.first?.sourceURL, link)
    }
    func testFailedSyncPreservesPlaylistAndBadgeAndChecksAreThrottled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        store.acceptImport(ImportedPlaylist(name: "Original", sourceURL: "https://www.deezer.com/playlist/123", tracks: [track("a")]))
        let id = try XCTUnwrap(store.currentPlaylist?.id)
        store.library.playlists[0].hasRemoteChanges = true
        await store.refreshPlaylist(id, apply: true, load: { _ in throw AudioFailure.network })
        XCTAssertEqual(store.currentPlaylist?.hasRemoteChanges, true)
        XCTAssertEqual(store.currentPlaylist?.importedTracks?.map(\.id), ["a"])
        XCTAssertNotNil(store.syncErrors[id])
        XCTAssertFalse(store.checkingPlaylists.contains(id))
        await store.checkPlaylistUpdates(load: { _ in XCTFail("Pas de nouvelle requête avant 15 minutes"); throw AudioFailure.network })
    }
    func testReorderingTriggersBadgeButLocalRenameDoesNot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        let snapshot = ImportedPlaylist(name: "Original", sourceURL: "https://www.deezer.com/playlist/123", tracks: [track("a"), track("b")])
        store.acceptImport(snapshot)
        let id = try XCTUnwrap(store.currentPlaylist?.id)
        store.renamePlaylist(id, to: "Local")
        await store.refreshPlaylist(id, apply: false, load: { _ in snapshot })
        XCTAssertEqual(store.currentPlaylist?.hasRemoteChanges, false)
        var reordered = snapshot; reordered.tracks.reverse()
        await store.refreshPlaylist(id, apply: false, load: { _ in reordered })
        XCTAssertEqual(store.currentPlaylist?.hasRemoteChanges, true)
    }
}

import XCTest
@testable import EasyMusic

@MainActor final class PlaylistDeletionTests: XCTestCase {
    func testDeleteCurrentPlaylistPreservesAudioOtherListsAndPersists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("audio.m4a"); try Data([1]).write(to: file)
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        let track = Track(id: "test", title: "Test", artist: "Artist", url: "https://example.com/test", source: "Test")
        let local = LocalTrack(track: track, path: file.path)
        let kept = Playlist(name: "Keep", trackIDs: [local.id])
        let removed = Playlist(name: "Remove", trackIDs: [local.id], importedTracks: [track], sourceURL: "https://www.deezer.com/playlist/1")
        store.library.tracks = [local]; store.library.playlists = [kept, removed]
        store.section = removed.id.uuidString
        store.syncErrors[removed.id] = "Error"
        store.deletePlaylist(removed.id)
        XCTAssertEqual(store.section, "library")
        XCTAssertEqual(store.library.playlists.map(\.id), [kept.id])
        XCTAssertEqual(store.visibleLocal.map(\.id), [local.id])
        XCTAssertNil(store.syncErrors[removed.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let reloaded = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        XCTAssertEqual(reloaded.library.playlists.map(\.id), [kept.id])
        XCTAssertEqual(reloaded.library.tracks.map(\.id), [local.id])
    }
    func testLateSyncCannotRecreateDeletedPlaylist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        let list = Playlist(name: "Remove", sourceURL: "https://www.deezer.com/playlist/1")
        store.library.playlists = [list]; store.section = "home"
        await store.refreshPlaylist(list.id, apply: true) { _ in
            store.deletePlaylist(list.id)
            return ImportedPlaylist(name: "Remote", sourceURL: list.sourceURL!, tracks: [])
        }
        XCTAssertTrue(store.library.playlists.isEmpty)
        XCTAssertEqual(store.section, "home")
        XCTAssertFalse(store.checkingPlaylists.contains(list.id))
    }
}

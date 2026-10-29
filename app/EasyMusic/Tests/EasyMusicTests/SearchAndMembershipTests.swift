import XCTest
@testable import EasyMusic

@MainActor final class SearchAndMembershipTests: XCTestCase {
    func testRankingIsStableAndExactTitleComesFirst() {
        let exact = Track(id: "1", title: "Blink", artist: "John", url: "https://example.com/1", source: "Test")
        let remix = Track(id: "2", title: "Blink remix", artist: "John", url: "https://example.com/2", source: "Test")
        let artist = CatalogItem(key: 1, name: "blink-182", subtitle: "", artwork: nil, kind: "artist")
        let first = SearchEntry.ranked(tracks: [remix, exact], collections: [artist], query: "BLINK")
        XCTAssertEqual(first.first?.track?.id, exact.id)
        XCTAssertEqual(first.map(\.id), SearchEntry.ranked(tracks: [exact, remix], collections: [artist], query: "blink").map(\.id))
    }
    func testPickerMembershipReusesLocalFileAcrossPlaylistsAndPersists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("audio.m4a"); try Data([1]).write(to: file)
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        let track = Track(id: "a", title: "Song", artist: "Artist", url: "https://example.com/a", source: "Test")
        let local = LocalTrack(track: track, path: file.path); store.library.tracks = [local]
        let first = try XCTUnwrap(store.createPlaylist("First", navigate: false))
        let second = try XCTUnwrap(store.createPlaylist("Second", navigate: false))
        XCTAssertEqual(store.section, "home")
        store.setMembership(track, in: first, included: true)
        store.setMembership(track, in: first, included: true)
        store.setMembership(track, in: second, included: true)
        XCTAssertEqual(store.library.playlists[0].trackIDs, [local.id])
        XCTAssertTrue(store.activeDownloads.isEmpty)
        store.setMembership(track, in: first, included: false)
        XCTAssertFalse(store.contains(track, in: store.library.playlists[0]))
        XCTAssertTrue(store.contains(track, in: store.library.playlists[1]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let restored = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        XCTAssertTrue(restored.contains(track, in: restored.library.playlists[1]))
    }
    func testQueuedTrackAddedToSeveralPlaylistsIsNotQueuedTwice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: root, observePlayback: false)
        let track = Track(id: "a", title: "Song", artist: "Artist", url: "https://example.com/a", source: "Test")
        store.pending = [track]
        let first = try XCTUnwrap(store.createPlaylist("First", navigate: false))
        let second = try XCTUnwrap(store.createPlaylist("Second", navigate: false))
        store.setMembership(track, in: first, included: true)
        store.setMembership(track, in: second, included: true)
        XCTAssertEqual(store.pending.count, 1)
        XCTAssertTrue(store.library.playlists.allSatisfy { store.contains(track, in: $0) })
        store.setMembership(track, in: first, included: false)
        XCTAssertFalse(store.contains(track, in: store.library.playlists[0]))
        XCTAssertTrue(store.contains(track, in: store.library.playlists[1]))
    }
}

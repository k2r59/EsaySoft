import XCTest
@testable import EasyMusic

final class PlaylistImportTests: XCTestCase {
    func testRecognizesOnlyTrustedPlaylistLinks() throws {
        XCTAssertEqual(try PlaylistImport.source("https://open.spotify.com/intl-fr/playlist/3cEYpjA9oz9GiPac4AsH4n?si=abc"), .spotify("3cEYpjA9oz9GiPac4AsH4n"))
        XCTAssertEqual(try PlaylistImport.source("https://www.deezer.com/fr/playlist/123"), .deezer(123))
        XCTAssertEqual(try PlaylistImport.source("https://music.youtube.com/watch?v=abcdefghijk&list=PL1234567890"), .youtube("PL1234567890"))
        for link in ["http://open.spotify.com/playlist/3cEYpjA9oz9GiPac4AsH4n", "https://open.spotify.com.evil.com/playlist/3cEYpjA9oz9GiPac4AsH4n", "file:///tmp/a", "https://music.youtube.com/playlist?list=RD1234567890", "https://www.deezer.com/track/123"] {
            XCTAssertThrowsError(try PlaylistImport.source(link))
        }
    }
    func testSpotifyMetadataAndCompletenessWarning() throws {
        let entity: [String: Any] = ["name": "My mix", "trackList": [
            ["uri": "spotify:track:4Cy0NHJ8Gh0xMdwyM9RkQm", "title": "All I Want", "subtitle": "LCD Soundsystem", "duration": 401440],
            ["uri": "spotify:episode:4Cy0NHJ8Gh0xMdwyM9RkQm", "title": "Podcast"]]]
        let json = try JSONSerialization.data(withJSONObject: ["props": ["pageProps": ["state": ["data": ["entity": entity]]]]])
        let html = "<script id=\"__NEXT_DATA__\" type=\"application/json\">\(String(decoding: json, as: UTF8.self))</script>"
        let playlist = try PlaylistImport.spotify(Data(html.utf8), key: "3cEYpjA9oz9GiPac4AsH4n")
        XCTAssertEqual(playlist.name, "My mix")
        XCTAssertEqual(playlist.tracks.count, 1)
        XCTAssertEqual(playlist.tracks[0].duration, 401.44)
        XCTAssertTrue(playlist.tracks[0].isCatalog)
        XCTAssertNotNil(playlist.warning)
        XCTAssertThrowsError(try PlaylistImport.spotify(Data("<html>Sign in</html>".utf8), key: "test"))
    }
    func testYouTubeOrderUnavailableTracksAndDuplicates() throws {
        let row: [String: Any] = ["title": "Mix", "playlist_count": 4, "entries": [
            ["id": "abcdefghijk", "title": "First", "uploader": "Artist"],
            ["id": "lmnopqrstuv", "title": "[Private video]"],
            ["id": "12345678901", "title": "Second"],
            ["id": "abcdefghijk", "title": "First"]]]
        let result = try PlaylistImport.youtube(row, url: "https://music.youtube.com/playlist?list=PL1234567890")
        XCTAssertEqual(result.tracks.map(\.title), ["First", "Second"])
        XCTAssertNotNil(result.warning)
        XCTAssertThrowsError(try PlaylistImport.youtube(["entries": []], url: "test"))
        XCTAssertThrowsError(try PlaylistImport.youtube(["entries": Array(repeating: NSNull(), count: 2001)], url: "test"))
    }
    @MainActor func testImportPersistsAndReusesLocalTracksWithoutDownloading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("library.json")
        let store = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        let track = Track(id: "YouTube:abcdefghijk", title: "First", artist: "Artist", url: "https://www.youtube.com/watch?v=abcdefghijk", source: "YouTube")
        let path = root.appendingPathComponent("audio.m4a")
        try Data([1]).write(to: path)
        var timed = track; timed.duration = 200
        var otherSource = timed; otherSource.id = "spotify:other"; otherSource.duration = 201
        XCTAssertTrue(Matching.sameRecording(timed, otherSource))
        otherSource.title = "First (Live)"
        XCTAssertFalse(Matching.sameRecording(timed, otherSource))
        let local = LocalTrack(track: track, path: path.path)
        store.library.tracks = [local]
        let imported = ImportedPlaylist(name: "My mix", sourceURL: "https://music.youtube.com/playlist?list=PL1234567890", tracks: [track], warning: "Partial")
        store.acceptImport(imported)
        let playlistID = store.currentPlaylist?.id
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.visibleLocal.map(\.id), [local.id])
        store.acceptImport(imported)
        XCTAssertEqual(store.library.playlists.count, 1)
        XCTAssertEqual(store.currentPlaylist?.id, playlistID)
        store.downloadPlaylist(try XCTUnwrap(store.currentPlaylist))
        XCTAssertTrue(store.pending.isEmpty)
        let restored = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        XCTAssertEqual(restored.library.playlists.first?.importedTracks?.first?.id, track.id)
        XCTAssertEqual(restored.library.playlists.first?.importWarning, "Partial")
    }
    func testOldPlaylistStillDecodes() throws {
        let data = Data("{\"id\":\"\(UUID())\",\"name\":\"Local\",\"trackIDs\":[]}".utf8)
        XCTAssertNil(try JSONDecoder().decode(Playlist.self, from: data).importedTracks)
    }
}

final class PlaylistImportLiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Essais réseau désactivés") }
    }
    func testPublicSpotifyPlaylist() async throws {
        let result = try await PlaylistImport.load("https://open.spotify.com/playlist/3cEYpjA9oz9GiPac4AsH4n")
        XCTAssertFalse(result.tracks.isEmpty)
        XCTAssertEqual(result.tracks.first?.title, "Api")
        XCTAssertNotNil(result.warning)
    }
    func testPublicDeezerPlaylist() async throws {
        let items = try await Catalog.playlists("jazz", limit: 1)
        let item = try XCTUnwrap(items.first)
        let result = try await PlaylistImport.load("https://www.deezer.com/playlist/\(item.key)")
        XCTAssertFalse(result.tracks.isEmpty)
        XCTAssertTrue(result.tracks.allSatisfy(\.isCatalog))
    }
    func testPublicYouTubeMusicPlaylist() async throws {
        let result = try await PlaylistImport.load("https://music.youtube.com/playlist?list=PLRBp0Fe2GpgmgoscNFLxNyBVSFVdYmFkq")
        XCTAssertFalse(result.tracks.isEmpty)
        XCTAssertTrue(result.tracks.allSatisfy { $0.source == "YouTube" && !$0.isCatalog })
    }
}

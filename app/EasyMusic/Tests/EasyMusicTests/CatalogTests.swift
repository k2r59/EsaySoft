import XCTest
@testable import EasyMusic

final class CatalogTests: XCTestCase {
    func testSearchFiltersUseContentTypes() {
        XCTAssertEqual(SearchMode.allCases.map(\.rawValue), ["Tout", "Styles", "Titres", "Albums", "Artistes"])
    }
    func testOldLibraryDecodesWithoutRecentCollections() throws {
        let value = try JSONDecoder().decode(Library.self, from: Data("{\"tracks\":[],\"playlists\":[]}".utf8))
        XCTAssertNil(value.recentCollections)
    }
    func testAlbumTracksKeepArtworkAndArtist() {
        let tracks = Catalog.tracks([["id": 42, "title": "A song", "duration": 123.0, "artist": ["name": "Artist"]]], artwork: "https://example.com/cover.jpg")
        XCTAssertEqual(tracks.first?.artwork, "https://example.com/cover.jpg")
        XCTAssertEqual(tracks.first?.artist, "Artist")
        XCTAssertEqual(tracks.first?.url, "https://www.deezer.com/track/42")
        XCTAssertEqual(tracks.first?.isCatalog, true)
    }
    func testGenreAliasesAndAccentNormalization() {
        XCTAssertEqual(Catalog.normalizeGenre("Électronique"), "electro")
        XCTAssertEqual(Catalog.normalizeGenre("hip-hop"), "rap/hip hop")
        XCTAssertEqual(Catalog.normalizeGenre("JAZZ"), "jazz")
    }
    func testMalformedCatalogRowsAreIgnored() {
        XCTAssertTrue(Catalog.items([["title": "Missing ID"]], kind: "album").isEmpty)
        XCTAssertTrue(Catalog.tracks([["id": 1]]).isEmpty)
    }
    func testDifferentCatalogKindsCannotHaveSameIdentity() {
        let row: [String: Any] = ["id": 1, "name": "Name"]
        XCTAssertNotEqual(Catalog.items([row], kind: "genre").first?.id, Catalog.items([row], kind: "artist").first?.id)
    }
}

@MainActor final class LibraryTests: XCTestCase {
    func testMultiplePlaylistsPersistenceAndDuplicateProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("library.json")
        let path = root.appendingPathComponent("song.m4a")
        try Data([1, 2, 3]).write(to: path)
        let store = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        let remote = Track(id: "1", title: "A song", artist: "An artist", url: "https://example.com/song", source: "Test")
        let local = LocalTrack(track: remote, path: path.path)
        store.library.tracks = [local]
        store.createPlaylist("First"); store.createPlaylist("Second")
        let first = store.library.playlists[0].id, second = store.library.playlists[1].id
        store.add(local, to: first); store.add(local, to: second); store.add(local, to: first)
        XCTAssertEqual(store.library.playlists[0].trackIDs, [local.id])
        XCTAssertEqual(store.library.playlists[1].trackIDs, [local.id])
        XCTAssertEqual(store.downloaded(remote)?.id, local.id)
        store.enqueue(remote)
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertNil(store.activeID)
        let reloaded = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        XCTAssertEqual(reloaded.library.playlists.count, 2)
        XCTAssertEqual(reloaded.library.playlists[1].trackIDs, [local.id])
        reloaded.remove(local, from: first)
        XCTAssertTrue(reloaded.library.playlists[0].trackIDs.isEmpty)
        XCTAssertEqual(reloaded.library.playlists[1].trackIDs, [local.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        try FileManager.default.removeItem(at: path)
        XCTAssertNil(reloaded.downloaded(remote), "Un fichier supprimé doit pouvoir être téléchargé à nouveau")
    }
}

final class HTTPFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("Unavailable".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class NetworkFailureTests: XCTestCase {
    func testUnavailableServiceReturnsReadableError() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HTTPFailureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await Engine.request(URL(string: "https://example.com")!, session: session)
            XCTFail("Une réponse 503 ne doit pas être traitée comme un succès")
        } catch { XCTAssertTrue(error.localizedDescription.contains("indisponible")) }
    }
}

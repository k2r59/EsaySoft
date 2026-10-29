import XCTest
@testable import EasyMusic

final class CatalogCoherenceTests: XCTestCase {
    func testServiceQuotaResponsesAreIdentifiedAndNeverCachedAsResults() {
        let quota = Data(#"{"error":{"code":4,"message":"Quota limit exceeded"}}"#.utf8)
        XCTAssertTrue(DeezerClient.isQuotaError(quota))
        XCTAssertTrue(DeezerClient.hasServiceError(quota))
        XCTAssertFalse(DeezerClient.isQuotaError(Data(#"{"data":[]}"#.utf8)))
    }
    func testEveryKnownGenreIsTreatedAsAThemeRatherThanAnArtistName() {
        for name in ["Pop", "Livres audio", "Rap/Hip Hop", "Rock", "Dance", "R&B", "Alternative", "Electro", "Folk", "Reggae", "Jazz", "Chanson française", "Country", "Classique", "Films/Jeux vidéo", "Metal", "Soul & Funk", "Blues", "Jeunesse", "Latino", "Musique africaine", "Musique arabe", "Musique asiatique", "Musique brésilienne", "Musique indienne"] {
            XCTAssertNotNil(Recommendations.genreID(name), name)
        }
    }
    func testSecondaryGenresCountButUnknownMetadataDoesNot() {
        XCTAssertEqual(Catalog.albumGenreIDs(["genre_id": 95, "genres": ["data": [["id": 95], ["id": 457]]]]), [95, 457])
        XCTAssertTrue(Catalog.albumGenreIDs(["genre_id": -1]).isEmpty)
    }
    func testGenreBrowsersRejectWrongCategoryDuplicatesAndUnavailableAlbums() async throws {
        let genre = CatalogItem(key: 457, name: "Livres audio", subtitle: "", artwork: nil, kind: "genre")
        let values = try await Catalog.albums(in: genre, loadRows: { path, _ in
            XCTAssertEqual(path, "chart/457/albums")
            return [["id": 1], ["id": 2], ["id": 1], ["id": 3], ["id": 4]]
        }, loadAlbum: { id in
            if id == 4 { throw MusicError.message("Unavailable") }
            if id == 3 { return ["id": 3, "title": "Unknown"] }
            return ["id": id, "title": id == 1 ? "A book" : "Unrelated rap", "genre_id": id == 1 ? 95 : 116,
                    "genres": ["data": [["id": id == 1 ? 457 : 116]]]]
        })
        XCTAssertEqual(values.map(\.key), [1])
        XCTAssertEqual(values.first?.kind, "audiobook")
    }
    func testAlbumOrderSurvivesDifferentResponseSpeeds() async {
        let result = await Catalog.verifiedAlbums([["id": 1], ["id": 2]], genreID: 129) { id in
            if id == 1 { try await Task.sleep(nanoseconds: 20_000_000) }
            return ["id": id, "title": "Jazz \(id)", "genre_id": 129]
        }
        XCTAssertEqual(result.compactMap { $0["id"] as? Int }, [1, 2])
    }
    func testTitleMatchesWholeWordsAndDoesNotTrustCreatorOrPartialArtistNames() {
        XCTAssertFalse(Recommendations.titleMatches("Blind test 90s", query: "blink"))
        XCTAssertFalse(Recommendations.titleMatches("House party", query: "John Dahlbäck"))
        XCTAssertTrue(Recommendations.titleMatches("100% John Dahlbäck", query: "John Dahlbäck"))
        XCTAssertTrue(Recommendations.titleMatches("Actu Chanson", query: "chanson française"))
        XCTAssertTrue(Recommendations.titleMatches("New Electronic", query: "électro"))
    }
    func testArtistPlaylistNeedsMatchingContentsNotJustMatchingTitle() {
        let rows = [["title": "Violin concerto", "artist": ["name": "Renaud Capuçon"]]]
        XCTAssertFalse(Recommendations.contentMatches(rows, query: "Renaud"))
        XCTAssertTrue(Recommendations.contentMatches([["title": "Mistral gagnant", "artist": ["name": "Renaud"]]], query: "Renaud"))
        XCTAssertFalse(Recommendations.contentMatches([], query: "Renaud"))
    }
    func testChartResolutionRejectsWrongArtistsAndVersionsAndPreservesOrder() async {
        let songs = [ChartSong(name: "Fille à Papa", artistName: "Vacra & La Rvfleuze", kind: "songs"), ChartSong(name: "Title", artistName: "Renaud", kind: "songs")]
        let wrong = Track(id: "wrong", title: "Title", artist: "Renaud Capuçon", url: "https://example.com", source: "Test")
        let result = await PublicCharts.resolve(songs) { query in
            if query.contains("Vacra") {
                return [Track(id: "right", title: "Fille à Papa", artist: "Vacra", url: "https://example.com", source: "Test")]
            }
            return [wrong, Track(id: "live", title: "Title (Live)", artist: "Renaud", url: "https://example.com", source: "Test")]
        }
        XCTAssertEqual(result.map(\.id), ["right"])
    }
    func testChartArtistMatchingNeverConfusesRenaudAndRenaudCapuconInEitherDirection() {
        let song = ChartSong(name: "Title", artistName: "Renaud Capuçon", kind: "songs")
        let track = Track(id: "a", title: "Title", artist: "Renaud", url: "https://example.com", source: "Test")
        XCTAssertFalse(PublicCharts.matches(track, song: song))
        var other = track; other.artist = "Renaud Capuçon"
        XCTAssertFalse(PublicCharts.matches(other, song: ChartSong(name: "Title", artistName: "Renaud", kind: "songs")))
        XCTAssertEqual(PublicCharts.creditedArtists("Vacra & La Rvfleuze"), ["vacra", "la rvfleuze"])
        XCTAssertEqual(PublicCharts.creditedArtists("Tyler, The Creator"), ["tyler the creator"])
    }
    func testUnavailableOfficialFeedFallsBackWithHonestAttribution() async {
        let track = Track(id: "fallback", title: "Song", artist: "Artist", url: "https://example.com", source: "Deezer")
        let result = await PublicCharts.fetch(load: { throw URLError(.timedOut) }, search: { _ in XCTFail("Ne pas rechercher sans classement"); return [] }, fallback: { [track] })
        XCTAssertEqual(result.source, "Classement Deezer")
        XCTAssertEqual(result.tracks.map(\.id), [track.id])
    }
    func testChartDecoderRejectsNonMusicMissingArtistAndMalformedIDs() throws {
        func row(kind: String = "Music", artist: String = "Artist", artistURL: String = "https://music.apple.com/fr/artist/artist/123", id: String = "456") -> [String: Any] {
            ["im:name": ["label": "Song"], "im:artist": ["label": artist, "attributes": ["href": artistURL]],
             "id": ["attributes": ["im:id": id]], "im:contentType": ["attributes": ["term": kind], "im:contentType": ["attributes": ["term": "Track"]]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["feed": ["entry": [row(), row(kind: "Podcast"), row(artist: ""), row(artistURL: "https://example.com/artist/123"), row(id: "not-a-song-id")]]])
        XCTAssertEqual(try PublicCharts.parse(data).map(\.name), ["Song"])
    }

}

final class CatalogCoherenceLiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Activer EASYMUSIC_NETWORK_TESTS=1 pour le contrôle des catalogues") }
    }
    func testAllGenreTilesResolveOnlyToAlbumsWithTheSelectedGenre() async throws {
        let genres = try await Catalog.search("", mode: .genres)
        XCTAssertGreaterThan(genres.count, 10)
        var verifiedCount = 0
        for genre in genres {
            let albums = try await Catalog.albums(in: genre, limit: 3)
            for item in albums {
                let row = try await Catalog.album(item.key)
                XCTAssertTrue(Catalog.albumGenreIDs(row).contains(genre.key), "\(genre.name) → \(item.name)")
                verifiedCount += 1
            }
            print("COHERENCE genre \(genre.key) \(genre.name): \(albums.count) vérifiés")
        }
        XCTAssertGreaterThan(verifiedCount, 30)
    }
    func testAudiobooksJazzRockAreDistinctAndAudiobooksOpenChapters() async throws {
        var ids: [Int: Set<Int>] = [:]
        for (key, name) in [(457, "Livres audio"), (129, "Jazz"), (152, "Rock")] {
            let values = try await Catalog.albums(in: CatalogItem(key: key, name: name, subtitle: "", artwork: nil, kind: "genre"), limit: 5)
            XCTAssertFalse(values.isEmpty)
            ids[key] = Set(values.map(\.key))
            print("COHERENCE \(name): \(values.map(\.name).joined(separator: "; "))")
            if key == 457 {
                XCTAssertTrue(values.allSatisfy { $0.kind == "audiobook" })
                let chapters = try await Catalog.tracks(in: XCTUnwrap(values.first))
                XCTAssertFalse(chapters.isEmpty)
                XCTAssertTrue(chapters.allSatisfy(\.isCatalog))
            }
        }
        XCTAssertTrue(ids[457]!.isDisjoint(with: ids[129]!))
        XCTAssertTrue(ids[457]!.isDisjoint(with: ids[152]!))
    }
    func testHomeCollectionsAndPersonalizedRenaudHaveVerifiedContent() async throws {
        var generalCount = 0
        for query in Recommendations.generalQueries {
            let items = await Catalog.relatedCollections(query, limit: 1)
            for item in items {
                XCTAssertTrue(Recommendations.titleMatches(item.name, query: query))
                let valid = await Catalog.playlistMatches(item, query: query)
                XCTAssertTrue(valid, "\(query) → \(item.name)")
            }
            generalCount += items.count
            print("COHERENCE accueil \(query): \(items.map(\.name))")
        }
        XCTAssertGreaterThanOrEqual(generalCount, 4)
        let renaud = await Catalog.relatedCollections("Renaud", limit: 2)
        XCTAssertFalse(renaud.isEmpty)
        XCTAssertFalse(renaud.contains { $0.name.contains("Capuçon") })
        print("COHERENCE Renaud: \(renaud.map(\.name))")
    }
    func testFrenchTopUsesActualOfficialFeedAndVerifiedCatalogMatches() async throws {
        let songs = try await PublicCharts.loadSongs()
        XCTAssertGreaterThanOrEqual(songs.count, 12)
        let tracks = await PublicCharts.resolve(songs, limit: 8)
        XCTAssertGreaterThanOrEqual(tracks.count, 4)
        XCTAssertEqual(Set(tracks.map(\.id)).count, tracks.count)
        XCTAssertTrue(tracks.allSatisfy { track in songs.contains { PublicCharts.matches(track, song: $0) } })
        print("COHERENCE Top France: \(tracks.map { $0.title + " — " + $0.artist })")
    }
}

private final class CatalogURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); count = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.deezer.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension CatalogCoherenceTests {
    func testCatalogRequestsAreCoalescedAndCachedWithoutSecondNetworkRequest() async throws {
        CatalogURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CatalogURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = DeezerClient(), url = URL(string: "https://api.deezer.com/album/123")!
        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<4 { group.addTask { try await client.request(url, session: session) } }
            for try await data in group { XCTAssertFalse(data.isEmpty) }
        }
        _ = try await client.request(url, session: session)
        XCTAssertEqual(CatalogURLProtocol.requests, 1)
    }
}

final class OfficialFeedStabilityTests: XCTestCase {
    func testITunesFeedAfterManyCatalogRequests() async throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Réseau désactivé") }
        let genres = try await Catalog.search("", mode: .genres)
        for genre in genres { _ = try await Catalog.albums(in: genre, limit: 3) }
        let data = try await Engine.request(URL(string: "https://itunes.apple.com/fr/rss/topsongs/limit=50/json")!)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let feed = try XCTUnwrap(root["feed"] as? [String: Any])
        let entries = try XCTUnwrap(feed["entry"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 50)
        print("ITUNES_STABILITY \(entries.count) entrées après parcours des \(genres.count) catégories")
    }
}

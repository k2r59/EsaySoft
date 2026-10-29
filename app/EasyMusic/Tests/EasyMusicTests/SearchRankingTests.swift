import XCTest
@testable import EasyMusic

final class SearchRankingTests: XCTestCase {
    func song(_ id: String, _ title: String, _ artist: String) -> Track {
        Track(id: id, title: title, artist: artist, url: "https://example.com/\(id)", source: "Deezer", isCatalog: true)
    }
    func testTitleAndArtistQueryRanksRenaudBeforeTheCover() {
        let title = "La ballade nord-irlandaise"
        let original = song("999", title + " (Sur les motifs de \"Water Is Deep\")", "Renaud")
        let cover = song("1", title, "Perrot Olivier")
        let namesake = song("2", title, "Renaud Capuçon")
        for query in [title + " Renaud", "Renaud " + title, "LA BALLADE NORD IRLANDAISE RENAUD"] {
            XCTAssertEqual(SearchEntry.ranked(tracks: [cover, namesake, original], collections: [], query: query).first?.track?.id, original.id)
        }
    }
    func testArtistSearchDoesNotTreatPartialNamesAsTheSameArtist() {
        let renaud = CatalogItem(key: 999, name: "Renaud", subtitle: "", artwork: nil, kind: "artist")
        let capucon = CatalogItem(key: 1, name: "Renaud Capuçon", subtitle: "", artwork: nil, kind: "artist")
        let entries = [capucon, renaud]
        XCTAssertEqual(SearchEntry.ranked(tracks: [], collections: entries, query: "Renaud").first?.id, renaud.id)
        XCTAssertEqual(SearchEntry.ranked(tracks: [], collections: entries, query: "Renaud Capucon").first?.id, capucon.id)
    }
    func testExactArtistTracksOutrankNamesakesForArtistOnlyQuery() {
        let singer = song("999", "Mistral gagnant", "Renaud")
        let violinist = song("1", "Méditation", "Renaud Capuçon")
        XCTAssertEqual(SearchEntry.ranked(tracks: [violinist, singer], collections: [], query: "Renaud").first?.track?.id, singer.id)
        XCTAssertEqual(SearchEntry.ranked(tracks: [singer, violinist], collections: [], query: "Renaud Capuçon").first?.track?.id, violinist.id)
    }
    func testExplicitVersionsRemainTheBestMatch() {
        let original = song("1", "Blink", "John Dahlbäck")
        for version in ["Remix", "Live", "Radio Edit", "Extended Mix", "Acoustic"] {
            let variant = song("999", "Blink - " + version, "John Dahlbäck")
            XCTAssertEqual(SearchEntry.ranked(tracks: [variant, original], collections: [], query: "Blink John Dahlback").first?.track?.id, original.id)
            XCTAssertEqual(SearchEntry.ranked(tracks: [original, variant], collections: [], query: "John Dahlback Blink " + version).first?.track?.id, variant.id)
        }
    }
    func testHomonymousArtistsKeepCatalogRelevanceInsteadOfIDOrder() {
        let providers = [999, 42, 1].map { CatalogItem(key: $0, name: "Renaud", subtitle: "", artwork: nil, kind: "artist") }
        XCTAssertEqual(SearchEntry.ranked(tracks: [], collections: providers, query: "Renaud").map(\.id), providers.map(\.id))
    }
    func testEqualTracksAndAlbumsKeepTheirProviderOrder() {
        let tracks = [song("999", "Blink", "John"), song("1", "Blink", "John")]
        let albums = [999, 1].map { CatalogItem(key: $0, name: "Blink", subtitle: "John", artwork: nil, kind: "album") }
        XCTAssertEqual(SearchEntry.ranked(tracks: tracks, collections: [], query: "Blink").compactMap { $0.track?.id }, tracks.map(\.id))
        XCTAssertEqual(SearchEntry.ranked(tracks: [], collections: albums, query: "Blink").map(\.id), albums.map(\.id))
    }
    func testEmptyQueryPreservesProviderOrder() {
        let tracks = [song("999", "Song B", "Artist"), song("1", "Song A", "Artist")]
        XCTAssertEqual(SearchEntry.ranked(tracks: tracks, collections: [], query: " \n ").compactMap { $0.track?.id }, tracks.map(\.id))
    }
    func testPublicCatalogRanksTheRequestedRecordingAndKeepsArtistRelevance() async throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Réseau désactivé") }
        let query = "La ballade nord-irlandaise Renaud"
        let tracks = try await Engine.deezer(query)
        let first = try XCTUnwrap(SearchEntry.ranked(tracks: tracks, collections: [], query: query).first?.track)
        XCTAssertEqual(first.artist, "Renaud")
        XCTAssertTrue(Matching.words(first.title).isSuperset(of: ["ballade", "nord", "irlandaise"]))
        let artists = try await Catalog.search("Renaud", mode: .artists)
        let expected = artists.filter { $0.name == "Renaud" }
        XCTAssertFalse(expected.isEmpty)
        let ordered = SearchEntry.ranked(tracks: [], collections: artists, query: "Renaud")
        XCTAssertEqual(ordered.first?.collection?.key, expected.first?.key)
        XCTAssertEqual(ordered.compactMap(\.collection).filter { $0.name == "Renaud" }.map(\.key), expected.map(\.key))
        print("SEARCH_QA meilleur résultat : \(first.artist) · \(first.title) ; artistes homonymes dans l’ordre public : \(expected.map(\.key))")
    }
}

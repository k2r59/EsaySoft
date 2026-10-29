import XCTest
@testable import EasyMusic

final class TrackCatalogRelationsTests: XCTestCase {
    let title = "La ballade nord-irlandaise"
    func target(_ id: String = "deezer:100") -> Track {
        Track(id: id, title: title, artist: "Renaud", duration: 217, url: "https://example.com/song", source: "Deezer", isCatalog: true)
    }
    func recording(_ id: Int = 100, artistID: Int = 21, name: String = "Renaud") -> [String: Any] {
        ["id": id, "title": title, "duration": 217, "artist": ["id": artistID, "name": name], "album": ["id": 42, "title": "Marchand de cailloux"]]
    }
    func testOnlyExactHomonymsAreOrderedByRealFanCounts() {
        let rows: [[String: Any]] = [
            ["id": 1, "name": "Renaud", "nb_fan": 44],
            ["id": 2, "name": "Renaud Capuçon", "nb_fan": 9_000_000],
            ["id": 21, "name": "Renaud", "nb_fan": 1_365_127]
        ]
        XCTAssertEqual(Catalog.rankArtistHomonyms(rows).compactMap { $0["id"] as? Int }, [21, 2, 1])
    }
    func testMissingOrEqualFanCountsPreserveOrder() {
        for counts in [[nil, 500], [500, 500]] as [[Int?]] {
            let rows = zip([99, 1], counts).map { id, count -> [String: Any] in
                var row: [String: Any] = ["id": id, "name": "Renaud"]
                if let count { row["nb_fan"] = count }
                return row
            }
            XCTAssertEqual(Catalog.rankArtistHomonyms(rows).compactMap { $0["id"] as? Int }, [99, 1])
        }
    }
    func testCatalogTrackUsesItsArtistRelationAndOriginalAlbum() async throws {
        let value = try await Catalog.relations(for: target(), loadTrack: {
            XCTAssertEqual($0, 100); return self.recording()
        }, searchTracks: { _ in XCTFail("The track already identifies its artist"); return [] }, loadAlbums: {
            XCTAssertEqual($0, 21)
            return [["id": 42, "title": "Marchand de cailloux"], ["id": 43, "title": "Wrong artist", "artist": ["id": 123]]]
        })
        XCTAssertEqual(value?.artist.key, 21)
        XCTAssertEqual(value?.albums.map(\.key), [42])
    }
    func testMismatchedMetadataDoesNotInventARelation() async throws {
        let value = try await Catalog.relations(for: target(), loadTrack: { _ in self.recording(999) }, searchTracks: { _ in XCTFail(); return [] }, loadAlbums: { _ in XCTFail(); return [] })
        XCTAssertNil(value)
    }
    func testRemoteTrackRequiresExactTitleAndArtistWithOneArtistIdentity() async throws {
        let value = try await Catalog.relations(for: target("youtube:one"), loadTrack: { _ in XCTFail(); return [:] }, searchTracks: { _ in
            [self.recording(1, artistID: 409258, name: "Renaud Capuçon"), self.recording()]
        }, loadAlbums: { XCTAssertEqual($0, 21); return [] })
        XCTAssertEqual(value?.artist.key, 21)
    }
    func testHomonymousRecordingsAreOmittedWhenIdentityIsAmbiguous() async throws {
        let value = try await Catalog.relations(for: target("soundcloud:one"), searchTracks: { _ in
            [self.recording(), self.recording(2, artistID: 117014712)]
        }, loadAlbums: { _ in XCTFail("No guessed artist"); return [] })
        XCTAssertNil(value)
    }
    func testUnrequestedVersionDoesNotEstablishArtistIdentity() async throws {
        var live = recording(); live["title"] = title + " (Live)"
        let value = try await Catalog.relations(for: target("youtube:one"), searchTracks: { _ in [live] }, loadAlbums: { _ in XCTFail(); return [] })
        XCTAssertNil(value)
    }
    func testCancelledMetadataLookupDoesNotTryAnotherArtist() async {
        do {
            _ = try await Catalog.relations(for: target(), loadTrack: { _ in throw CancellationError() }, searchTracks: { _ in XCTFail(); return [] }, loadAlbums: { _ in XCTFail(); return [] })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testLiveRenaudRelationsBelongToSinger21AndTheSelectedRecording() async throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Réseau désactivé") }
        let tracks = try await Engine.deezer(title + " Renaud")
        let track = try XCTUnwrap(SearchEntry.ranked(tracks: tracks, collections: [], query: title + " Renaud").first?.track)
        let loaded = try await Catalog.relations(for: track)
        let relation = try XCTUnwrap(loaded)
        XCTAssertEqual(relation.artist.key, 21)
        let album = try XCTUnwrap(relation.albums.first)
        let albumTracks = try await Catalog.tracks(in: album)
        XCTAssertTrue(albumTracks.contains { $0.id == track.id })
        let artists = try await Catalog.search("Renaud", mode: .artists)
        XCTAssertEqual(SearchEntry.ranked(tracks: [], collections: artists, query: "Renaud").first?.collection?.key, 21)
        print("RELATIONS_QA \(track.title) → Renaud ID21 → \(album.name), piste \(track.id) présente")
    }
}

import XCTest
import AVFoundation
@testable import EasyMusic

final class LiveSourceTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Activer EASYMUSIC_NETWORK_TESTS=1 pour les essais réseau") }
    }
    func testHomeChartsContainRealTracksAndArtwork() async throws {
        let hits = try await Catalog.charts()
        XCTAssertEqual(hits.count, 12)
        XCTAssertTrue(hits.allSatisfy { !$0.title.isEmpty && $0.artwork != nil && $0.isCatalog })
    }
    func testHomeMixesAndPlaylistTracks() async throws {
        let mixes = await Catalog.homeMixes()
        XCTAssertGreaterThanOrEqual(mixes.count, 4)
        XCTAssertEqual(Set(mixes.map(\.id)).count, mixes.count)
        let playlist = try XCTUnwrap(mixes.first)
        let tracks = try await Catalog.tracks(in: playlist)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertEqual(Set(tracks.map(\.id)).count, tracks.count)
    }
    func testTitleSearchAndPreview() async throws {
        let tracks = try await Engine.deezer("Daft Punk")
        XCTAssertFalse(tracks.isEmpty)
        let preview = try XCTUnwrap(tracks.first?.preview).replacingOccurrences(of: "http://", with: "https://")
        let data = try await Engine.request(URL(string: preview)!)
        XCTAssertGreaterThan(data.count, 1000)
    }
    func testAlbumSearchAndAllTracks() async throws {
        let albums = try await Catalog.search("Random Access Memories", mode: .albums)
        let album = try XCTUnwrap(albums.first { $0.key == 6575789 })
        let tracks = try await Catalog.tracks(in: album)
        XCTAssertEqual(tracks.count, 13)
        XCTAssertTrue(tracks.contains { $0.title.contains("Instant Crush") })
    }
    func testArtistSearchAndTopTracks() async throws {
        let artists = try await Catalog.search("Daft Punk", mode: .artists)
        let artist = try XCTUnwrap(artists.first { $0.key == 27 })
        let tracks = try await Catalog.tracks(in: artist)
        XCTAssertFalse(tracks.isEmpty)
    }
    func testStyleSearchAndArtists() async throws {
        let genres = try await Catalog.search("jazz", mode: .genres)
        let genre = try XCTUnwrap(genres.first)
        let artists = try await Catalog.artists(in: genre)
        XCTAssertFalse(artists.isEmpty)
    }
    func testDirectDeezerAlbum() async throws {
        let (name, tracks) = try await Catalog.direct(URL(string: "https://www.deezer.com/fr/album/6575789")!)
        XCTAssertEqual(name, "Random Access Memories")
        XCTAssertEqual(tracks.count, 13)
    }
    func testSpotifyPublicLink() async throws {
        let title = try await Engine.spotifyTitle(URL(string: "https://open.spotify.com/track/2takcwOaAZWiXQijPHIx7B")!)
        XCTAssertFalse(title.isEmpty)
    }
    func testYouTubeSearchAndAudioFormats() async throws {
        let tracks = try await Engine.search("Big Buck Bunny Blender", source: "YouTube", count: 2)
        XCTAssertFalse(tracks.isEmpty)
        let (_, formats) = try await Engine.inspect("https://www.youtube.com/watch?v=aqz-KE-bpKQ")
        XCTAssertFalse(formats.isEmpty)
        XCTAssertFalse(formats.contains { $0.codec == "none" })
    }
    func testYouTubePreviewIsPlayableAndLimitedToThirtySeconds() async throws {
        let track = Track(id: "preview-youtube", title: "Big Buck Bunny", artist: "Blender", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", source: "YouTube")
        let url = try await Engine.previewClip(track)
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration.seconds, 1)
        XCTAssertLessThan(duration.seconds, 31)
    }
    func testSoundCloudPreviewIsPlayableAndLimitedToThirtySeconds() async throws {
        let tracks = try await Engine.search("Daft Punk", source: "SoundCloud", count: 1)
        let track = try XCTUnwrap(tracks.first)
        let url = try await Engine.previewClip(track)
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration.seconds, 1)
        XCTAssertLessThan(duration.seconds, 31)
    }
    func testSoundCloudSearch() async throws {
        let tracks = try await Engine.search("Daft Punk", source: "SoundCloud", count: 2)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertTrue(tracks.allSatisfy { $0.url.hasPrefix("https://soundcloud.com/") })
    }
}

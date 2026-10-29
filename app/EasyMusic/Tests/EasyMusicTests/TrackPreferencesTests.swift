import XCTest
@testable import EasyMusic

@MainActor final class TrackPreferencesTests: XCTestCase {
    private func fixture() throws -> (MusicStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyMusic-Preferences-QA-" + UUID().uuidString)
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        return (MusicStore(storageURL: root.appendingPathComponent("library.json"), downloadFolder: music, observePlayback: false), root)
    }

    private func track(_ id: String = "one") -> Track {
        Track(id: "spotify:" + id, title: "Soushkin - 7 Inch Edit", artist: "Dream Your Dream", duration: 231.426,
              url: "https://open.spotify.com/track/" + id, source: "Spotify", isCatalog: true)
    }

    func testOldLibraryWithoutPreferencesLoadsAndCanPersistNewPreferences() throws {
        let (initial, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let playlistID = UUID()
        let legacy = "{\"tracks\":[],\"playlists\":[{\"id\":\"\(playlistID)\",\"name\":\"Legacy\",\"trackIDs\":[]}]}"
        try Data(legacy.utf8).write(to: initial.storage)

        let store = MusicStore(storageURL: initial.storage, downloadFolder: initial.folder, observePlayback: false)
        XCTAssertNil(store.notice)
        XCTAssertNil(store.library.trackPreferences)
        XCTAssertTrue(store.likedTracks.isEmpty)
        XCTAssertFalse(store.isLiked(track()))
        XCTAssertEqual(store.rating(for: track()), 0)
        store.setLiked(true, for: track())
        store.setRating(4, for: track())

        let restored = MusicStore(storageURL: store.storage, downloadFolder: store.folder, observePlayback: false)
        XCTAssertNil(restored.notice)
        XCTAssertEqual(restored.library.playlists.first?.id, playlistID)
        XCTAssertEqual(restored.library.playlists.first?.name, "Legacy")
        XCTAssertTrue(restored.isLiked(track()))
        XCTAssertEqual(restored.rating(for: track()), 4)
        XCTAssertEqual(restored.preference(for: track())?.id, store.preference(for: track())?.id)
    }

    func testOnePreferenceIsSharedAcrossProvidersAndVersionPunctuation() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let spotify = track()
        var deezer = spotify
        deezer.id = "deezer:118313368"; deezer.url = "https://www.deezer.com/track/118313368"
        deezer.source = "Deezer"; deezer.title = "Soushkin (7 Inch Edit)"; deezer.duration = 231
        var quoted = deezer
        quoted.id = "youtube:other"; quoted.url = "https://www.youtube.com/watch?v=other"
        quoted.title = "Soushkin (7'' Edit)"; quoted.source = "YouTube"

        store.setLiked(true, for: spotify)
        let originalID = store.preference(for: spotify)?.id
        store.setRating(5, for: deezer)
        store.setLiked(true, for: quoted)
        XCTAssertEqual(store.library.trackPreferences?.count, 1)
        XCTAssertEqual(store.likedTracks.count, 1)
        for alias in [spotify, deezer, quoted] {
            XCTAssertTrue(store.isLiked(alias))
            XCTAssertEqual(store.rating(for: alias), 5)
            XCTAssertEqual(store.preference(for: alias)?.id, originalID)
        }
        store.setLiked(false, for: quoted)
        XCTAssertFalse(store.isLiked(spotify))
        XCTAssertEqual(store.rating(for: spotify), 5)
        XCTAssertTrue(store.likedTracks.isEmpty)
    }

    func testPreferenceDoesNotLeakToAnotherVersionOrArtist() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = track()
        store.setLiked(true, for: original)
        store.setRating(4, for: original)
        var remix = original
        remix.id = "deezer:remix"; remix.url = "https://www.deezer.com/track/remix"
        remix.title = "Soushkin (7 Inch Edit Remix)"
        var otherArtist = original
        otherArtist.id = "deezer:other-artist"; otherArtist.url = "https://www.deezer.com/track/other-artist"
        otherArtist.artist = "Another Artist"
        for other in [remix, otherArtist] {
            XCTAssertNil(store.preference(for: other))
            XCTAssertFalse(store.isLiked(other))
            XCTAssertEqual(store.rating(for: other), 0)
        }
        store.setRating(2, for: remix)
        XCTAssertEqual(store.rating(for: original), 4)
        XCTAssertEqual(store.rating(for: remix), 2)
        XCTAssertEqual(store.library.trackPreferences?.count, 2)
    }

    func testRatingsAcceptOneThroughFiveClampAndClear() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let song = track()
        for value in 1...5 {
            store.setRating(value, for: song)
            XCTAssertEqual(store.rating(for: song), value)
            XCTAssertEqual(store.preference(for: song)?.rating, value)
            XCTAssertFalse(store.isLiked(song))
        }
        store.setRating(Int.max, for: song)
        XCTAssertEqual(store.rating(for: song), 5)
        store.setRating(0, for: song)
        XCTAssertEqual(store.rating(for: song), 0)
        XCTAssertNil(store.preference(for: song))
        store.setRating(3, for: song)
        store.setRating(Int.min, for: song)
        XCTAssertEqual(store.rating(for: song), 0)
        XCTAssertNil(store.preference(for: song))
    }

    func testLikeAndRatingCanBeRemovedIndependently() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let song = track()
        store.setLiked(true, for: song)
        store.setRating(4, for: song)
        store.setLiked(false, for: song)
        XCTAssertFalse(store.isLiked(song))
        XCTAssertEqual(store.rating(for: song), 4)
        XCTAssertNotNil(store.preference(for: song))
        store.setLiked(true, for: song)
        store.setRating(0, for: song)
        XCTAssertTrue(store.isLiked(song))
        XCTAssertEqual(store.rating(for: song), 0)
        XCTAssertNil(store.preference(for: song)?.rating)
        XCTAssertEqual(store.likedTracks.map(\.id), [song.id])
        store.setLiked(false, for: song)
        XCTAssertNil(store.preference(for: song))
        XCTAssertTrue(store.likedTracks.isEmpty)
        let restored = MusicStore(storageURL: store.storage, downloadFolder: store.folder, observePlayback: false)
        XCTAssertNil(restored.preference(for: song))
    }

    func testLikingAndRatingRemoteTracksNeverDownloadOrStartPlayback() async throws {
        let (store, root) = try fixture()
        defer { store.cancelRequestedPlayback(); try? FileManager.default.removeItem(at: root) }
        var downloads = 0, resolutions = 0
        store.downloadWorker = { _, _, _, _ in downloads += 1; throw AudioFailure.network }
        store.streamResolver = { _, _ in resolutions += 1; throw AudioFailure.network }
        store.setLiked(true, for: track())
        store.setRating(5, for: track())
        await Task.yield()
        XCTAssertEqual(downloads, 0); XCTAssertEqual(resolutions, 0)
        XCTAssertTrue(store.pending.isEmpty); XCTAssertTrue(store.activeDownloads.isEmpty)
        XCTAssertTrue(store.library.tracks.isEmpty)
        XCTAssertNil(store.currentTrack); XCTAssertNil(store.requestedPlayback)
        XCTAssertNil(store.player.currentItem)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.folder.path).isEmpty)
    }

    func testMembershipInTwoPlaylistsPreservesPreferencesAfterRemovalAndReload() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let song = track()
        store.setLiked(true, for: song); store.setRating(3, for: song)
        let preferenceID = store.preference(for: song)?.id
        let first = try XCTUnwrap(store.createPlaylist("One", navigate: false))
        let second = try XCTUnwrap(store.createPlaylist("Two", navigate: false))
        store.setMembership(song, in: first, included: true)
        store.setMembership(song, in: second, included: true)
        XCTAssertTrue(store.library.playlists.allSatisfy { store.contains(song, in: $0) })
        XCTAssertEqual(store.preference(for: song)?.id, preferenceID)
        store.setMembership(song, in: first, included: false)
        XCTAssertFalse(store.contains(song, in: store.library.playlists[0]))
        XCTAssertTrue(store.contains(song, in: store.library.playlists[1]))
        XCTAssertTrue(store.isLiked(song)); XCTAssertEqual(store.rating(for: song), 3)
        store.setMembership(song, in: second, included: false)

        let restored = MusicStore(storageURL: store.storage, downloadFolder: store.folder, observePlayback: false)
        XCTAssertTrue(restored.library.playlists.allSatisfy { !restored.contains(song, in: $0) })
        XCTAssertEqual(restored.preference(for: song)?.id, preferenceID)
        XCTAssertTrue(restored.isLiked(song)); XCTAssertEqual(restored.rating(for: song), 3)
        XCTAssertTrue(restored.library.tracks.isEmpty)
        XCTAssertTrue(store.pending.isEmpty); XCTAssertTrue(store.activeDownloads.isEmpty)
    }

    func testLikedTracksExcludeRatingOnlyAndSupplyTheirOwnPlaybackQueue() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = track("first")
        var second = track("second"); second.title = "Second song"
        var ratingOnly = track("rating-only"); ratingOnly.title = "Rated only"
        store.setLiked(true, for: first)
        store.setLiked(true, for: second)
        store.setRating(5, for: ratingOnly)
        XCTAssertEqual(Set(store.likedTracks.map(\.id)), Set([first.id, second.id]))
        store.section = "liked"
        store.preparePlaybackQueue(for: first)
        XCTAssertEqual(store.playbackQueue.map(\.id), store.likedTracks.map(\.id))
        XCTAssertFalse(store.playbackQueue.contains { $0.id == ratingOnly.id })
        XCTAssertNil(store.currentTrack)
    }
}

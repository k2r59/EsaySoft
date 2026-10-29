import XCTest
@testable import EasyMusic

final class EngineTests: XCTestCase {
    func testOnlyAccessibleAudioFormatsAreOffered() {
        let formats = Engine.formats(["formats": [
            ["format_id": "audio", "acodec": "opus", "vcodec": "none", "ext": "webm", "abr": 128],
            ["format_id": "protected", "acodec": "aac", "vcodec": "none", "ext": "m4a", "has_drm": true],
            ["format_id": "video", "acodec": "aac", "vcodec": "h264", "ext": "mp4"],
            ["format_id": "silent", "acodec": "none", "vcodec": "h264", "ext": "mp4"]
        ]])
        XCTAssertEqual(formats.map(\.id), ["audio"])
    }
    func testMatchingRejectsCoverAndWrongDuration() {
        let target = Track(id: "catalog", title: "Get Lucky", artist: "Daft Punk", duration: 369, url: "", source: "Deezer", isCatalog: true)
        let exact = Track(id: "1", title: "Daft Punk - Get Lucky (Official Audio)", artist: "Daft Punk", duration: 369, url: "", source: "YouTube")
        let cover = Track(id: "2", title: "Daft Punk - Get Lucky cover", artist: "Someone", duration: 369, url: "", source: "YouTube")
        let wrong = Track(id: "3", title: "Other song", artist: "Unknown", duration: 120, url: "", source: "YouTube")
        XCTAssertGreaterThan(Matching.score(exact, for: target), 0.85)
        XCTAssertLessThan(Matching.score(cover, for: target), 0.85)
        XCTAssertLessThan(Matching.score(wrong, for: target), 0.85)
    }
    func testURLAllowlistRejectsSpoofedHostsAndLocalFiles() {
        XCTAssertTrue(Engine.isSupported(URL(string: "https://artist.bandcamp.com/track/song")!))
        XCTAssertFalse(Engine.isSupported(URL(string: "https://youtube.com.attacker.example/foo")!))
        XCTAssertFalse(Engine.isSupported(URL(string: "file:///etc/passwd")!))
    }
    func testDownloadPassesURLAsLiteralArgument() {
        let track = Track(id: "1", title: "title", artist: "artist", url: "https://example.com/$(touch bad)", source: "test")
        let args = Engine.downloadArguments(track: track, format: nil, folder: URL(fileURLWithPath: "/tmp/Music Folder"))
        XCTAssertEqual(args.suffix(2), ["--", track.url])
        XCTAssertTrue(args.contains("/tmp/Music Folder"))
        XCTAssertTrue(args.contains("bestaudio"))
    }
    func testPlaylistPersistenceKeepsOrder() throws {
        let a = UUID(), b = UUID()
        let library = Library(playlists: [Playlist(name: "My playlist", trackIDs: [b, a])])
        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded.playlists.first?.trackIDs, [b, a])
    }
}

final class TransferTests: XCTestCase {
    func testNamesCannotEscapeExportDirectory() {
        XCTAssertEqual(Transfer.safeName("../../\nMy/Playlist"), ".. ..  My Playlist")
        XCTAssertEqual(Transfer.safeName(".."), "Playlist")
        XCTAssertFalse(Transfer.safeName("A\r\n#EXTINF:evil").contains("\n"))
    }
    func testExportPreservesFilesAndPlaylistOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.mp3")
        let bytes = Data([1, 2, 3]); try bytes.write(to: source)
        let track = LocalTrack(track: Track(id: "test", title: "Title", artist: "Artist", duration: 5, url: "", source: "local"), path: source.path)
        let folder = try await Transfer.export([track], name: "Test", into: root)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("001 - Artist - Title.mp3")), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let list = try String(contentsOf: folder.appendingPathComponent("playlist.m3u8"))
        XCTAssertTrue(list.contains("001 - Artist - Title.mp3"))
        let second = try await Transfer.export([track], name: "Test", into: root)
        XCTAssertNotEqual(folder, second)
    }
}

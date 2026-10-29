import XCTest
@testable import EasyMusic

final class AudioMetadataTests: XCTestCase {
    func testUsesAudioBitrateAndFallsBackToContainerForVBR() {
        XCTAssertEqual(AudioMetadata.parse(Data(#"{"streams":[{"bit_rate":"192000"}],"format":{"bit_rate":"200000"}}"#.utf8)), 192)
        XCTAssertEqual(AudioMetadata.parse(Data(#"{"streams":[{}],"format":{"bit_rate":"129000"}}"#.utf8)), 129)
        XCTAssertNil(AudioMetadata.parse(Data(#"{"streams":[{"bit_rate":"N/A"}]}"#.utf8)))
    }
    func testUnknownBitrateIsNeverInvented() {
        let track = Track(id: "test", title: "Test", artist: "Artist", url: "", source: "Test")
        XCTAssertEqual(LocalTrack(track: track, path: "/tmp/a.mp3").bitrateLabel, "— kb/s")
        XCTAssertEqual(LocalTrack(track: track, path: "/tmp/a.mp3", bitrateKbps: 255.6).bitrateLabel, "≈ 256 kb/s")
    }
}

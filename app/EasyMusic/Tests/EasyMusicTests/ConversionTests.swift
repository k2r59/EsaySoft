import XCTest
import AVFoundation
@testable import EasyMusic

final class ConversionTests: XCTestCase {
    func testLocalConversionCreatesPlayableAudioAndPreservesOriginal() async throws {
        guard Engine.executable("ffmpeg") != nil else { throw XCTSkip("FFmpeg non installé") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("source.wav")
        let output = root.appendingPathComponent("export.mp3")
        var data = Data()
        func text(_ value: String) { data.append(value.data(using: .ascii)!) }
        func word(_ value: UInt16) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func dword(_ value: UInt32) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        text("RIFF"); dword(88236); text("WAVEfmt "); dword(16); word(1); word(1); dword(44100); dword(88200); word(2); word(16); text("data"); dword(88200)
        data.append(Data(repeating: 0, count: 88200)); try data.write(to: input)
        try await Engine.convert(input, to: output, title: "Test", artist: "EasyMusic")
        XCTAssertEqual(try Data(contentsOf: input), data)
        let asset = AVURLAsset(url: output)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration.seconds, 0.9)
    }
}

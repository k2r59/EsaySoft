import XCTest
@testable import EasyMusic

final class DJMetadataTests: XCTestCase {
    func testAllTwentyFourCamelotKeysAndFrenchNames() throws {
        let minor = ["G#m", "D#m", "A#m", "Fm", "Cm", "Gm", "Dm", "Am", "Em", "Bm", "F#m", "C#m"]
        let major = ["B", "F#", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E"]
        for number in 1...12 {
            for (suffix, names) in [("A", minor), ("B", major)] {
                let code = "\(number)\(suffix)"
                let value = try XCTUnwrap(MusicalKey.parse(code))
                XCTAssertEqual(value, MusicalKey.parse(names[number - 1]))
                XCTAssertEqual(value.camelot, code)
                XCTAssertFalse(value.name.isEmpty)
                XCTAssertEqual(value, MusicalKey.parse(value.name))
                let encoded = try JSONEncoder().encode(value)
                XCTAssertEqual(try JSONDecoder().decode(MusicalKey.self, from: encoded), value)
            }
        }
        XCTAssertEqual(MusicalKey.parse("8A")?.name, "La mineur")
        XCTAssertEqual(MusicalKey.parse("8B")?.name, "Do majeur")
    }
    func testEnharmonicKeysAndStrictTagParsing() {
        for pair in [("C#m", "Ré bémol mineur"), ("Bb major", "La♯ majeur"), ("F♯ minor", "Sol bemol min"), ("B#", "Do")] {
            XCTAssertEqual(MusicalKey.parse(pair.0), MusicalKey.parse(pair.1))
            XCTAssertNotNil(MusicalKey.parse(pair.0))
        }
        for value in ["", " ", "0A", "13B", "8A and 9A", "C major or A minor", "G dorian", "120", "H", "o", "Am remix"] {
            XCTAssertNil(MusicalKey.parse(value), value)
        }
        XCTAssertNotEqual(MusicalKey.parse("A"), MusicalKey.parse("Am"))
    }
    func testZeroNaNInfiniteBooleanAndInvalidBPMRemainUnknown() {
        for value: Any in [0, -1, Double.nan, Double.infinity, true, false, "NaN", "inf", "0", "128 BPM", ""] {
            XCTAssertNil(DJMetadata.validBPM(value), "\(value)")
        }
        XCTAssertEqual(DJMetadata.validBPM(156.01), 156.01)
        XCTAssertEqual(DJMetadata.validBPM(" 128.5 "), 128.5)
        XCTAssertNil(DJMetadata.validBPM(nil))
    }
    func testTagsRetainTheirSourceAndDoNotGuessMissingValues() {
        let value = DJMetadata.tags(["format": ["tags": ["TBPM": "156.01", "TKEY": "Am"]]])
        XCTAssertEqual(value.bpm, 156.01); XCTAssertEqual(value.key?.camelot, "8A")
        XCTAssertEqual(value.bpmSource, "Fichier"); XCTAssertEqual(value.keySource, "Fichier")
        let stream = DJMetadata.tags(["streams": [["tags": ["bpm": "128", "initial_key": "Dbm"]]]])
        XCTAssertEqual(stream.bpm, 128); XCTAssertEqual(stream.key?.camelot, "12A")
        let unknown = DJMetadata.tags(["format": ["tags": ["BPM": "0", "key": "unknown"]]])
        XCTAssertNil(unknown.bpm); XCTAssertNil(unknown.key)
        XCTAssertNil(unknown.bpmSource); XCTAssertNil(unknown.keySource)
    }
    func testPCM16WaveParserUnderstandsStreamingHeaderWithoutWritingAFile() throws {
        func word(_ value: UInt16) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
        func long(_ value: UInt32) -> [UInt8] { word(UInt16(value & 65535)) + word(UInt16(value >> 16)) }
        var bytes = Array("RIFF".utf8) + long(.max) + Array("WAVEfmt ".utf8) + long(16)
        bytes += word(1) + word(1) + long(22050) + long(44100) + word(2) + word(16)
        bytes += Array("data".utf8) + long(.max)
        for sample: Int16 in [0, 32767, -32768, 16384] { bytes += word(UInt16(bitPattern: sample)) }
        let decoded = try DJMetadata.pcm16Wave(Data(bytes))
        XCTAssertEqual(decoded.count, 4)
        XCTAssertEqual(decoded[0], 0); XCTAssertEqual(decoded[1], Float(32767) / 32768)
        XCTAssertEqual(decoded[2], -1); XCTAssertEqual(decoded[3], 0.5)
        bytes[22] = 2
        XCTAssertThrowsError(try DJMetadata.pcm16Wave(Data(bytes)))
        XCTAssertThrowsError(try DJMetadata.pcm16Wave(Data("not audio".utf8)))
    }
    func testSilenceShortAudioAndSinglePitchHaveNoInventedKeyOrTempo() throws {
        let rate = 22050.0
        let silence = try DJMetadata.analyze(samples: [Float](repeating: 0, count: Int(rate * 12)), sampleRate: rate)
        XCTAssertNil(silence.bpm); XCTAssertNil(silence.key)
        let short = try DJMetadata.analyze(samples: [0, 1, 0], sampleRate: rate)
        XCTAssertNil(short.bpm); XCTAssertNil(short.key)
        let tone = (0..<Int(rate * 12)).map { Float(0.3 * sin(2 * .pi * 220 * Double($0) / rate)) }
        let ambiguous = try DJMetadata.analyze(samples: tone, sampleRate: rate)
        XCTAssertNil(ambiguous.key, "Une note isolée ne distingue pas majeur et mineur")
        XCTAssertNil(ambiguous.bpm)
    }
    func testSyntheticRhythmicPulsesHaveTheRequestedTempoWithoutOctaveFolding() throws {
        let rate = 22050.0
        for bpm in [90.0, 128.0, 156.0] {
            let samples = (0..<Int(rate * 24)).map { index -> Float in
                let time = Double(index) / rate, phase = time.truncatingRemainder(dividingBy: 60 / bpm)
                return phase < 0.08 ? Float(sin(2 * .pi * 70 * phase) * exp(-phase * 45)) : 0
            }
            let result = try DJMetadata.analyze(samples: samples, sampleRate: rate)
            XCTAssertEqual(try XCTUnwrap(result.bpm, "Tempo \(bpm)"), bpm, accuracy: 1.5)
            XCTAssertEqual(result.bpmSource, "Estimation · audio")
        }
    }
    func testSyntheticMajorProgressionProducesAStableEstimatedKey() throws {
        let rate = 22050.0
        let chords = [[60, 64, 67], [53, 57, 60], [55, 59, 62]]
        let samples = (0..<Int(rate * 24)).map { index -> Float in
            let time = Double(index) / rate, position = time.truncatingRemainder(dividingBy: 2)
            let chord = chords[position < 1.2 ? 0 : position < 1.6 ? 1 : 2]
            return Float(chord.enumerated().reduce(0.0) { sum, item in
                let frequency = 440 * pow(2, Double(item.element - 69) / 12)
                return sum + (item.offset == 0 ? 0.25 : 0.18) * sin(2 * .pi * frequency * time)
            })
        }
        let result = try DJMetadata.analyze(samples: samples, sampleRate: rate)
        XCTAssertEqual(result.key, MusicalKey.parse("C major"))
        XCTAssertEqual(result.keySource, "Estimation · audio")
    }
    func testCancelledRequestDoesNotFetchOrAnalyzeAudio() async {
        let task = Task {
            try Task.checkCancellation()
            return try await DJMetadata().info(for: Track(id: "test", title: "Song", artist: "Artist", url: "https://example.com", source: "Test"), localPath: nil)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testRemoteAnalysisIsOffByDefaultAndUnknownTrackStaysUnknown() async throws {
        let track = Track(id: "test", title: "Unknown", artist: "Unknown", url: "https://example.invalid/audio", source: "Test", preview: "https://example.invalid/preview")
        let result = try await DJMetadata().info(for: track, localPath: nil)
        XCTAssertNil(result.bpm); XCTAssertNil(result.key)
    }
}

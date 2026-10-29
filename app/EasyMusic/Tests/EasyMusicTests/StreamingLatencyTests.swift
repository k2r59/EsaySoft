import XCTest
@testable import EasyMusic

final class StreamingLatencyTests: XCTestCase {
    private func candidate(_ url: String = "https://www.youtube.com/watch?v=FTCGdQOCuAw", source: String = "YouTube") -> Track {
        Track(id: "latency-fixture", title: "Soushkin (7 Inch Edit)", artist: "Dream Your Dream", duration: 234,
              url: url, source: source)
    }

    private func metadata(_ name: String = "fast", duration: Double = 234) -> [String: Any] {
        ["url": "https://media.example/\(name).m3u8", "vcodec": "none", "acodec": "mp4a.40.2",
         "ext": "mp4", "protocol": "m3u8_native", "duration": duration, "format_id": "234"]
    }

    private func isFast(_ args: [String]) -> Bool { args.contains("--extractor-args") }

    func testFastYouTubeSuccessDoesNotRunCompleteExtraction() async throws {
        let song = candidate()
        var reads: [[String]] = [], caps: [TimeInterval] = [], checked: [URL] = []
        let result = try await AudioStreaming.candidateStream(song, expectedDuration: 234, read: { args, timeout in
            reads.append(args); caps.append(timeout)
            XCTAssertTrue(self.isFast(args))
            return self.metadata()
        }, validate: { checked.append($0.url) })
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(caps, [5])
        XCTAssertEqual(checked, [result.url])
        XCTAssertEqual(result.source.id, song.id)
        XCTAssertEqual(result.source.title, song.title)
        XCTAssertEqual(result.source.artist, song.artist)
        XCTAssertEqual(result.source.duration, 234)
    }

    func testFastAndCompleteArgumentsResolveAudioOnlyWithoutDownload() {
        let url = "https://www.youtube.com/watch?v=literal&label=$(ignored)"
        for fast in [true, false] {
            let args = AudioStreaming.extractionArguments(url, fast: fast)
            XCTAssertEqual(Array(args.suffix(2)), ["--", url])
            XCTAssertTrue(args.contains("--skip-download"))
            XCTAssertTrue(args.contains("--dump-single-json"))
            XCTAssertEqual(isFast(args), fast)
            for option in ["-o", "-x", "--no-simulate", "--download-sections", "--video-multistreams"] {
                XCTAssertFalse(args.contains(option), option)
            }
            for branch in AudioStreaming.formatSelection.split(separator: "/") {
                XCTAssertTrue(branch.contains("[vcodec=none]"))
            }
        }
    }

    func testReadFailureFallsBackToCompleteProfileOfSameCandidate() async throws {
        let song = candidate()
        var profiles: [Bool] = [], caps: [TimeInterval] = [], validated = 0
        let result = try await AudioStreaming.candidateStream(song, expectedDuration: 234, read: { args, timeout in
            profiles.append(self.isFast(args)); caps.append(timeout)
            XCTAssertEqual(Array(args.suffix(2)), ["--", song.url])
            if self.isFast(args) { throw AudioFailure.network }
            return self.metadata("complete")
        }, validate: { _ in validated += 1 })
        XCTAssertEqual(profiles, [true, false]); XCTAssertEqual(caps, [5, 15])
        XCTAssertEqual(validated, 1)
        XCTAssertEqual(result.url.lastPathComponent, "complete.m3u8")
        XCTAssertEqual(result.source.id, song.id)
    }

    func testIncompatibleFastFormatFallsBackBeforeValidation() async throws {
        var profiles: [Bool] = [], checked: [String] = []
        let result = try await AudioStreaming.candidateStream(candidate(), expectedDuration: 234, read: { args, _ in
            profiles.append(self.isFast(args))
            var json = self.metadata(self.isFast(args) ? "incompatible" : "complete")
            if self.isFast(args) { json["acodec"] = "opus"; json["ext"] = "webm" }
            return json
        }, validate: { checked.append($0.url.lastPathComponent) })
        XCTAssertEqual(profiles, [true, false])
        XCTAssertEqual(checked, ["complete.m3u8"])
        XCTAssertEqual(result.url.lastPathComponent, "complete.m3u8")
    }

    func testWrongFastDurationFallsBackWithoutAcceptingLongMix() async throws {
        var profiles: [Bool] = [], checked: [String] = []
        let result = try await AudioStreaming.candidateStream(candidate(), expectedDuration: 234, read: { args, _ in
            profiles.append(self.isFast(args))
            return self.metadata(self.isFast(args) ? "wrong-duration" : "complete", duration: self.isFast(args) ? 3_600 : 234)
        }, validate: { checked.append($0.url.lastPathComponent) })
        XCTAssertEqual(profiles, [true, false])
        XCTAssertEqual(checked, ["complete.m3u8"])
        XCTAssertEqual(result.source.duration, 234)
    }

    func testPlayerValidationFailureFallsBackToCompleteExtraction() async throws {
        var profiles: [Bool] = [], checked: [String] = []
        let result = try await AudioStreaming.candidateStream(candidate(), expectedDuration: 234, read: { args, _ in
            profiles.append(self.isFast(args))
            return self.metadata(self.isFast(args) ? "bad-player-timing" : "complete")
        }, validate: { stream in
            checked.append(stream.url.lastPathComponent)
            if stream.url.lastPathComponent == "bad-player-timing.m3u8" { throw AudioFailure.unavailable }
        })
        XCTAssertEqual(profiles, [true, false])
        XCTAssertEqual(checked, ["bad-player-timing.m3u8", "complete.m3u8"])
        XCTAssertEqual(result.url.lastPathComponent, "complete.m3u8")
    }

    func testDRMPreviewAndVideoRemainRejectedInBothProfiles() async {
        let invalid: [(String, Any)] = [("has_drm", true), ("is_preview", true), ("vcodec", "h264")]
        for (key, value) in invalid {
            var profiles: [Bool] = [], validations = 0
            do {
                _ = try await AudioStreaming.candidateStream(candidate(), expectedDuration: 234, read: { args, _ in
                    profiles.append(self.isFast(args))
                    var json = self.metadata(); json[key] = value
                    return json
                }, validate: { _ in validations += 1 })
                XCTFail("Le profil complet doit aussi refuser \(key)")
            } catch {
                XCTAssertFalse(error is CancellationError)
            }
            XCTAssertEqual(profiles, [true, false], key)
            XCTAssertEqual(validations, 0, key)
        }
    }

    func testCancellationDuringReadNeverStartsCompleteProfile() async {
        var reads = 0, validations = 0
        do {
            _ = try await AudioStreaming.candidateStream(candidate(), expectedDuration: 234, read: { _, _ in
                reads += 1
                throw CancellationError()
            }, validate: { _ in validations += 1 })
            XCTFail("Annulation attendue")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(validations, 0)
    }

    func testCancellationDuringValidationNeverStartsCompleteProfile() async {
        var reads = 0, validations = 0
        do {
            _ = try await AudioStreaming.candidateStream(candidate(), expectedDuration: 234, read: { _, _ in
                reads += 1
                return self.metadata()
            }, validate: { _ in validations += 1; throw CancellationError() })
            XCTFail("Annulation attendue")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(validations, 1)
    }

    func testCancelledReadReturningMetadataStillCannotValidateOrFallback() async {
        var reads = 0, validations = 0
        let task = Task {
            try await AudioStreaming.candidateStream(self.candidate(), expectedDuration: 234, read: { _, _ in
                reads += 1
                withUnsafeCurrentTask { $0?.cancel() }
                return self.metadata()
            }, validate: { _ in validations += 1 })
        }
        do { _ = try await task.value; XCTFail("Annulation attendue malgré le résultat tardif") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(validations, 0)
    }

    func testSoundCloudAndOtherServicesUseOnlyCompleteProfile() async throws {
        for (url, source) in [("https://soundcloud.com/artist/song", "SoundCloud"), ("https://artist.bandcamp.com/track/song", "Bandcamp")] {
            var profiles: [Bool] = [], caps: [TimeInterval] = []
            _ = try await AudioStreaming.candidateStream(candidate(url, source: source), expectedDuration: 234, read: { args, timeout in
                profiles.append(self.isFast(args)); caps.append(timeout)
                XCTAssertEqual(Array(args.suffix(2)), ["--", url])
                return self.metadata("complete")
            }, validate: { _ in })
            XCTAssertEqual(profiles, [false]); XCTAssertEqual(caps, [15])
        }
    }

    func testNonYouTubeFailureDoesNotRetryTheSameProfile() async {
        var reads = 0
        do {
            _ = try await AudioStreaming.candidateStream(candidate("https://soundcloud.com/artist/song", source: "SoundCloud"), expectedDuration: 234,
                                                       read: { _, _ in reads += 1; throw AudioFailure.network }, validate: { _ in XCTFail("Aucun flux") })
            XCTFail("Erreur attendue")
        } catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }

    func testFastProfileUsesHostIdentityAndRejectsMisleadingSuffixes() {
        for url in ["https://youtube.com/watch?v=x", "https://www.youtube.com/watch?v=x", "https://music.youtube.com/watch?v=x", "https://YOUTUBE.COM/watch?v=x", "https://youtu.be/x"] {
            XCTAssertTrue(AudioStreaming.hasFastProfile(url), url)
        }
        for url in ["https://youtube.com.example.org/watch?v=x", "https://www.youtube.com.example.org/watch?v=x", "https://notyoutube.com/watch?v=x", "https://youtu.be.example.org/x", "https://youtube.com@evil.example/watch?v=x", "https://example.org/youtube.com", "youtube.com/watch?v=x"] {
            XCTAssertFalse(AudioStreaming.hasFastProfile(url), url)
        }
    }
}

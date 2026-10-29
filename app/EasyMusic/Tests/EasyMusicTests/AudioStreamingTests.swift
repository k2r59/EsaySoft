import XCTest
import AVFoundation
@testable import EasyMusic

final class AudioStreamingTests: XCTestCase {
    func song(_ id: String, source: String = "YouTube", catalog: Bool = false) -> Track {
        Track(id: id, title: "A song", artist: "Artist", duration: 180, url: "https://example.com/\(id)", source: source, isCatalog: catalog)
    }
    func stream(_ track: Track) -> AudioStream { AudioStream(url: URL(string: "https://example.com/audio.m4a")!, source: track) }
    func testArgumentsOnlyResolveAudioAndNeverWriteOrDownloadMedia() {
        let args = AudioStreaming.extractionArguments("https://example.com/song")
        XCTAssertTrue(args.contains("--skip-download")); XCTAssertTrue(args.contains("--dump-single-json"))
        for branch in AudioStreaming.formatSelection.split(separator: "/") { XCTAssertTrue(branch.contains("[vcodec=none]")) }
        XCTAssertFalse(args.contains("--no-simulate")); XCTAssertFalse(args.contains("--download-sections")); XCTAssertFalse(args.contains("-o")); XCTAssertFalse(args.contains("-x"))
    }
    func testSelectedFormatRejectsVideoDRMPreviewAndIncompatibleCodec() throws {
        let valid: [String: Any] = ["url": "https://example.com/audio.m4a", "vcodec": "none", "acodec": "mp4a.40.2", "ext": "m4a", "duration": 180]
        XCTAssertEqual(try AudioStreaming.selectedStream(valid, source: song("a")).url.pathExtension, "m4a")
        for (key, value) in [("vcodec", "h264" as Any), ("has_drm", true), ("format_note", "preview"), ("is_preview", true), ("acodec", "opus"), ("url", "file:///tmp/audio.m4a")] {
            var invalid = valid; invalid[key] = value
            XCTAssertThrowsError(try AudioStreaming.selectedStream(invalid, source: song("a")), key)
        }
    }
    func testDurationMismatchCannotChooseAnHourLongMixForASong() {
        XCTAssertFalse(AudioStreaming.durationMatches(3600, 217))
        XCTAssertFalse(AudioStreaming.durationMatches(30, 217))
        XCTAssertTrue(AudioStreaming.durationMatches(208, 217))
    }
    func testUserAgentUsesOnlyThePublicAssetOptionAndRejectsNewlines() throws {
        var json: [String: Any] = ["url": "https://example.com/audio.m4a", "vcodec": "none", "acodec": "aac", "ext": "m4a", "http_headers": ["User-Agent": "Public-Agent"]]
        XCTAssertEqual(try AudioStreaming.selectedStream(json, source: song("a")).userAgent, "Public-Agent")
        json["http_headers"] = ["User-Agent": "Agent\r\nHeader: injected"]
        XCTAssertNil(try AudioStreaming.selectedStream(json, source: song("a")).userAgent)
    }
    func testDirectSourceDoesNotRunSearchAndCreatesNoLibraryEntry() async throws {
        let target = song("direct")
        let result = try await AudioStreaming.run(target: target, search: { _, _ in XCTFail("Unnecessary search"); return [] }, extract: { self.stream($0) })
        XCTAssertEqual(result.source.id, target.id)
    }
    func testCatalogTriesTheFastCompatibleSourceBeforeYouTube() async throws {
        let target = song("catalog", source: "Deezer", catalog: true)
        let result = try await AudioStreaming.run(target: target, search: { _, service in
            XCTAssertEqual(service, "SoundCloud")
            return [self.song("full", source: service)]
        }, extract: { self.stream($0) })
        XCTAssertEqual(result.source.source, "SoundCloud")
    }
    func testSourceFailureSelectsAnotherReliableSourceAndHonorsExclusions() async throws {
        let target = song("protected", source: "SoundCloud"), excluded = song("old"), replacement = song("replacement")
        var tried: [String] = []
        let result = try await AudioStreaming.run(target: target, excluding: [excluded.url], search: { _, service in
            XCTAssertEqual(service, "YouTube"); return [excluded, replacement]
        }, extract: { track in
            tried.append(track.id)
            if track.id == target.id { throw AudioFailure.protectedAudio }
            return self.stream(track)
        })
        XCTAssertEqual(tried, [target.id, replacement.id]); XCTAssertEqual(result.source.id, replacement.id)
    }
    func testCancellationIsNotReplacedByAnotherSource() async {
        do {
            _ = try await AudioStreaming.run(target: song("direct"), search: { _, _ in XCTFail("Cancelled"); return [] }, extract: { _ in throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testNoReliableVersionReturnsClearErrorWithoutUsingPreview() async {
        var wrong = song("wrong"); wrong.title = "Other song"; wrong.artist = "Someone"
        do {
            _ = try await AudioStreaming.run(target: song("catalog", catalog: true), search: { _, _ in [wrong] }, extract: { _ in XCTFail("Wrong recording"); return self.stream(wrong) })
            XCTFail("Expected failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("flux audio complet")) }
    }
}

final class AudioStreamingLiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Réseau désactivé") }
    }
    func testCancellingRealResolutionReturnsPromptly() async throws {
        let target = Track(id: "cancel-stream", title: "Big Buck Bunny", artist: "Blender", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", source: "YouTube")
        let task = Task { try await AudioStreaming.resolve(target) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let cancelled = Date(); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(cancelled), 3)
    }
    func testRenaudResolvesToCompletePlayableRemoteAudioWithoutLocalMedia() async throws {
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/EasyMusic"),
                     FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyMusic/Previews")]
        func contents() -> [String] { roots.flatMap { root in ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).map { root.path + "/" + $0 } }.sorted() }
        let before = contents()
        let found = try await Engine.deezer("Renaud La ballade nord-irlandaise")
        let track = try XCTUnwrap(found.first { $0.artist == "Renaud" && $0.title.lowercased().contains("ballade") })
        let started = Date()
        let stream = try await AudioStreaming.resolve(track)
        XCTAssertEqual(stream.url.scheme, "https")
        let asset = stream.makeAsset()
        let playable = try await asset.load(.isPlayable), duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video), audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(playable); XCTAssertTrue(video.isEmpty); XCTAssertFalse(audio.isEmpty)
        XCTAssertGreaterThan(duration, 180); XCTAssertLessThan(duration, 250)
        XCTAssertEqual(contents(), before)
        print("STREAM_QA Renaud | \(stream.source.source) | \(duration)s | resolution \(Date().timeIntervalSince(started))s | aucune écriture audio")
    }
    @MainActor func testRemoteAudioActuallyStartsPlayingBeyondPreviewWithoutSavingFile() async throws {
        let target = Track(id: "qa-stream", title: "Big Buck Bunny", artist: "Blender", duration: 596, url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", source: "YouTube")
        let stream = try await AudioStreaming.resolve(target)
        let item = AVPlayerItem(asset: stream.makeAsset()), player = AVPlayer()
        player.isMuted = true; player.replaceCurrentItem(with: item); player.play()
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        let end = Date().addingTimeInterval(15)
        while player.currentTime().seconds < 0.2 && Date() < end && item.status != .failed { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNil(item.error); XCTAssertGreaterThan(player.currentTime().seconds, 0.1)
        await player.seek(to: CMTime(seconds: 45, preferredTimescale: 600))
        player.play()
        let seekEnd = Date().addingTimeInterval(10)
        while player.currentTime().seconds < 45.1 && Date() < seekEnd { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertGreaterThan(player.currentTime().seconds, 45)
        print("STREAM_QA \(stream.source.source) AVPlayer lecture distante au-delà de 45s, durée \(item.duration.seconds)s")
    }
}

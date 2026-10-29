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
    func testExplicitSevenAndTwelveInchVersionsCannotReplaceEachOther() {
        var seven = song("seven"), twelve = song("twelve")
        seven.title = "Soushkin (7 Inch Edit)"; twelve.title = "Soushkin (12 Inch Edit)"
        XCTAssertEqual(Matching.score(twelve, for: seven), 0)
        XCTAssertEqual(Matching.score(seven, for: twelve), 0)
        for title in ["Soushkin (7\" Edit)", "Soushkin (7'' Edit)", "Soushkin (7inch Edit)"] {
            var equivalent = seven; equivalent.title = title
            XCTAssertGreaterThanOrEqual(Matching.score(equivalent, for: seven), 0.85)
        }
        var unspecified = seven; unspecified.title = "Soushkin (Edit)"
        XCTAssertGreaterThan(Matching.score(unspecified, for: seven), 0, "Une taille non renseignée n’est pas une contradiction explicite")
        seven.title = "The Long Song Name From Tonight (7 Inch Edit)"
        unspecified.title = "The Long Song Name From Tonight (Edit)"
        XCTAssertGreaterThanOrEqual(Matching.score(unspecified, for: seven), 0.85)
    }
    func testRequestedVersionAndCreditedArtistCannotBeSubstituted() throws {
        var requested = song("requested"); requested.title = "Soushkin (7 Inch Edit Remix)"
        var original = song("original"); original.title = "Soushkin (7 Inch Edit)"
        XCTAssertLessThan(Matching.score(original, for: requested), 0.85)
        requested.title = "Méditation"; requested.artist = "Renaud"
        let homonym = try XCTUnwrap(Engine.track(["id": "homonym", "title": "Méditation", "duration": 180, "channel": "Renaud Capuçon - Topic"], source: "YouTube"))
        XCTAssertEqual(homonym.creditedArtist, "Renaud Capuçon")
        XCTAssertLessThan(Matching.score(homonym, for: requested), 0.85)
        var exact = homonym; exact.creditedArtist = "Renaud"; exact.artist = "Renaud"
        XCTAssertGreaterThanOrEqual(Matching.score(exact, for: requested), 0.85)
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
    func testFastMatchingSourceDoesNotWaitForSlowProvider() async throws {
        let target = song("catalog", source: "Deezer", catalog: true)
        let start = Date()
        let result = try await AudioStreaming.run(target: target, search: { _, service in
            if service == "YouTube" { try await Task.sleep(nanoseconds: 2_000_000_000) }
            return [self.song("full", source: service)]
        }, extract: { self.stream($0) })
        XCTAssertEqual(result.source.source, "SoundCloud")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
    func testSlowExtractionCannotBlockOtherPlayableProvider() async throws {
        let start = Date()
        let result = try await AudioStreaming.run(target: song("catalog", catalog: true), search: { _, service in
            if service == "YouTube" { try await Task.sleep(nanoseconds: 50_000_000) }
            return [self.song(service, source: service)]
        }, extract: { song in
            if song.source == "SoundCloud" { try await Task.sleep(nanoseconds: 2_000_000_000) }
            return self.stream(song)
        })
        XCTAssertEqual(result.source.source, "YouTube")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
    func testSourceFailureSelectsAnotherReliableSourceAndHonorsExclusions() async throws {
        let target = song("protected", source: "SoundCloud"), excluded = song("old"), replacement = song("replacement")
        var tried: [String] = []
        let result = try await AudioStreaming.run(target: target, excluding: [excluded.url], search: { _, service in
            return service == "YouTube" ? [excluded, replacement] : []
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
    func testHLSWithoutCodecStillRequiresExplicitAudioOnlyMetadata() throws {
        var json: [String: Any] = ["url": "https://example.com/audio.m3u8", "vcodec": "none", "ext": "mp4", "protocol": "m3u8_native"]
        XCTAssertNoThrow(try AudioStreaming.selectedStream(json, source: song("hls")))
        json["vcodec"] = "h264"
        XCTAssertThrowsError(try AudioStreaming.selectedStream(json, source: song("video")))
        json["vcodec"] = "none"; json["protocol"] = "https"
        XCTAssertThrowsError(try AudioStreaming.selectedStream(json, source: song("unknown")))
    }
    func testBadTimingFallsBackToAnotherAudioFormatOfSameRecording() async throws {
        let target = song("same-recording")
        let dash = AudioStream(url: URL(string: "https://example.com/dash.m4a")!, source: target)
        let hls = AudioStream(url: URL(string: "https://example.com/native.m3u8")!, source: target)
        var attempts: [URL] = []
        let result = try await AudioStreaming.firstPlayable([dash, hls]) { stream in
            attempts.append(stream.url)
            if stream.url == dash.url { throw AudioFailure.unavailable }
        }
        XCTAssertEqual(attempts, [dash.url, hls.url]); XCTAssertEqual(result.url, hls.url)
    }
    func testStreamCacheExpiresAndDoesNotReuseFailedSource() async {
        let cache = AudioStreamCache(), target = song("cache"), now = Date(timeIntervalSince1970: 1_000)
        let resolved = AudioStream(url: URL(string: "https://example.com/audio.m3u8?expire=1100")!, source: target)
        await cache.insert(resolved, for: target, now: now)
        let hit = await cache.value(for: target, now: now.addingTimeInterval(10))
        XCTAssertEqual(hit?.url, resolved.url)
        let expired = await cache.value(for: target, now: now.addingTimeInterval(71))
        XCTAssertNil(expired)
        await cache.insert(resolved, for: target, now: now)
        let excluded = await cache.value(for: target, excluding: [target.url], now: now)
        XCTAssertNil(excluded)
        let removed = await cache.value(for: target, now: now)
        XCTAssertNil(removed)
    }
}

final class AudioStreamingLiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["EASYMUSIC_NETWORK_TESTS"] == "1" else { throw XCTSkip("Réseau désactivé") }
    }
    @MainActor func testReportedTracksPlayWithCorrectDurationAndFastReplay() async throws {
        let tracks = [
            Track(id: "deezer:118313368", title: "Soushkin (7 Inch Edit)", artist: "Dream Your Dream", duration: 231, url: "https://www.deezer.com/track/118313368", source: "Deezer", isCatalog: true),
            Track(id: "qa-belgium-rave", title: "Belgium Rave (Original Remastered Mix)", artist: "Dream Your Dream", duration: 243, url: "https://www.deezer.com/", source: "Deezer", isCatalog: true),
            Track(id: "YouTube:Y4uOM7s38XA", title: "Suprême NTM - Ma Benz (Clip officiel) ft. Lord Kossity", artist: "SupremeNTMVEVO", url: "https://www.youtube.com/watch?v=Y4uOM7s38XA", source: "YouTube")
        ]
        for target in tracks {
            let start = Date(), stream = try await AudioStreaming.resolve(target)
            let item = AVPlayerItem(asset: stream.makeAsset()), player = AVPlayer()
            player.isMuted = true; player.replaceCurrentItem(with: item); player.play()
            defer { player.pause(); player.replaceCurrentItem(with: nil) }
            let end = Date().addingTimeInterval(10)
            while player.currentTime().seconds < 0.2 && Date() < end && item.status != .failed { try await Task.sleep(nanoseconds: 50_000_000) }
            XCTAssertNil(item.error); XCTAssertGreaterThan(player.currentTime().seconds, 0.1, target.title)
            let coldStart = Date().timeIntervalSince(start)
            let expected = try XCTUnwrap(target.duration ?? stream.source.duration)
            XCTAssertEqual(item.duration.seconds, expected, accuracy: 5, target.title)
            XCTAssertFalse(item.tracks.contains { $0.assetTrack?.mediaType == .video })
            XCTAssertTrue(item.tracks.contains { $0.assetTrack?.mediaType == .audio })
            await player.seek(to: CMTime(seconds: 45, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play(); try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertGreaterThan(player.currentTime().seconds, 45, target.title)
            let replayStart = Date(), replay = try await AudioStreaming.resolve(target)
            let replayTime = Date().timeIntervalSince(replayStart)
            XCTAssertEqual(replay.url, stream.url); XCTAssertLessThan(replayTime, 0.2)
            player.pause(); player.replaceCurrentItem(with: AVPlayerItem(asset: replay.makeAsset())); player.play()
            let replayEnd = Date().addingTimeInterval(5)
            while player.currentTime().seconds < 0.2 && Date() < replayEnd { try await Task.sleep(nanoseconds: 50_000_000) }
            XCTAssertGreaterThan(player.currentTime().seconds, 0.1)
            let warmStart = Date().timeIntervalSince(replayStart)
            XCTAssertLessThan(warmStart, 3, target.title)
            print("STREAM_REGRESSION \(target.title) | audio \(item.duration.seconds)s | premier démarrage \(coldStart)s | relance \(warmStart)s | résolution répétée \(replayTime)s")
        }
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
        // HLS media tracks are populated on the ready player item. validate checks audio, video and duration there.
        try await AudioStreaming.validate(stream, expectedDuration: track.duration)
        XCTAssertTrue(playable)
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

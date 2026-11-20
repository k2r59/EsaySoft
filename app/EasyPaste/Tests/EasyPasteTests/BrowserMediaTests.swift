import XCTest
@testable import EasyPaste

final class BrowserMediaTests: XCTestCase {
    var request: [String: Any] { ["protocol": 1, "type": "media", "nonce": "0123456789abcdef0123456789abcdef", "extensionVersion": "0.3.0", "mode": "video", "url": "https://www.youtube.com/watch?v=abcdefghijk"] }
    func testMediaProtocolRejectsUnexpectedFieldsOriginsAndLocalURLs() throws {
        let data = try JSONSerialization.data(withJSONObject: request)
        XCTAssertEqual(try BrowserMediaRequest.validated(data, origin: BrowserBridgeProtocol.origin).mode, "video")
        XCTAssertThrowsError(try BrowserMediaRequest.validated(data, origin: "https://youtube.com"))
        for patch: [String: Any] in [["protocol": true], ["mode": "shell"], ["command": "touch file"], ["nonce": "../../escape"], ["url": "file:///etc/passwd"], ["url": "https://user:pass@example.com/video"], ["url": "http://localhost/video"], ["url": "http://127.0.0.1/a"], ["url": "http://172.16.0.1/a"], ["url": "https://example.com/\n"], ["url": "https://example.com/" + String(repeating: "x", count: 4096)]] {
            var bad = request; bad.merge(patch) { _, new in new }
            XCTAssertThrowsError(try BrowserMediaRequest.validated(JSONSerialization.data(withJSONObject: bad), origin: BrowserBridgeProtocol.origin))
        }
    }
    func testBridgeQueuesOnlyWhenEnabledAndCleansFailedLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try JSONSerialization.data(withJSONObject: request)
        var launches = 0
        let disabled = try BrowserMediaBridge.accept(data, origin: BrowserBridgeProtocol.origin, config: nil, root: root) { launches += 1 }
        XCTAssertEqual((try JSONSerialization.jsonObject(with: disabled) as? [String: Any])?["status"] as? String, "disabled")
        XCTAssertEqual(launches, 0)
        let config = BrowserBridgeConfiguration(enabled: true, browser: .chrome, generation: "new-session")
        let reply = try BrowserMediaBridge.accept(data, origin: BrowserBridgeProtocol.origin, config: config, root: root) { launches += 1 }
        XCTAssertEqual((try JSONSerialization.jsonObject(with: reply) as? [String: Any])?["status"] as? String, "queued")
        let files = try FileManager.default.contentsOfDirectory(at: BrowserMediaRequest.folder(root: root), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1); XCTAssertEqual(launches, 1)
        let queued = try XCTUnwrap(BrowserExtensionFiles.read(BrowserMediaRequest.self, from: files[0]))
        XCTAssertEqual(queued.generation, "new-session"); XCTAssertEqual(queued.mode, "video")
        let failure = try BrowserMediaBridge.accept(data, origin: BrowserBridgeProtocol.origin, config: config, root: root) { throw CocoaError(.fileNoSuchFile) }
        XCTAssertEqual((try JSONSerialization.jsonObject(with: failure) as? [String: Any])?["status"] as? String, "error")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: BrowserMediaRequest.folder(root: root), includingPropertiesForKeys: nil).count, 1)
    }
    func testArgumentsAreBoundedSingleMediaAndNeverShellOrCookieCommands() throws {
        let url = "https://example.com/watch?q=$(touch%20bad)&v=hello"
        let output = URL(fileURLWithPath: "/tmp/test folder")
        for mode in ["video", "audio"] {
            let args = try BrowserMediaEngine.arguments(url: url, mode: mode, output: output)
            XCTAssertEqual(Array(args.suffix(2)), ["--", url])
            XCTAssertTrue(args.contains("--ignore-config")); XCTAssertTrue(args.contains("--no-overwrites")); XCTAssertTrue(args.contains("--no-playlist"))
            XCTAssertFalse(args.contains("--cookies-from-browser")); XCTAssertFalse(args.contains("--exec"))
            XCTAssertTrue(args.contains(output.appendingPathComponent("media.%(ext)s").path))
            XCTAssertTrue(args.contains(mode == "video" ? "mp4" : "mp3"))
        }
    }
    func testMetadataRejectsPlaylistsDRMLiveAndWrongStreamKind() throws {
        func json(_ obj: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self) }
        let regular: [String: Any] = ["title": "Test", "formats": [["vcodec": "h264", "acodec": "aac"]]]
        XCTAssertEqual(try BrowserMediaEngine.metadata(json(regular), mode: "video"), "Test")
        XCTAssertEqual(try BrowserMediaEngine.metadata(json(["title": "Direct", "formats": [["ext": "mp4"]]]), mode: "video"), "Direct")
        for patch: [String: Any] in [["_type": "playlist"], ["has_drm": true], ["is_live": true], ["formats": [["vcodec": "none", "acodec": "aac"]]], ["formats": [["has_drm": true, "vcodec": "h264"]]]] {
            var bad = regular; bad.merge(patch) { _, new in new }
            XCTAssertThrowsError(try BrowserMediaEngine.metadata(json(bad), mode: "video"))
        }
    }
    @MainActor func testRevokedOrExpiredQueuedJobsAreDiscardedWithoutStartingDownloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try BrowserExtensionFiles.write(BrowserBridgeConfiguration(enabled: true, browser: .chrome, generation: "new"), to: root.appendingPathComponent("configuration.json"))
        for (generation, age) in [("old", 0.0), ("new", -400.0)] {
            let item = BrowserMediaRequest(id: UUID(), url: "https://example.com/video.mp4", mode: "video", generation: generation, created: Date().addingTimeInterval(age))
            try BrowserExtensionFiles.write(item, to: BrowserMediaRequest.folder(root: root).appendingPathComponent(item.id.uuidString + ".json"))
        }
        let model = BrowserMediaDownloads(root: root); model.consume()
        XCTAssertTrue(model.jobs.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: BrowserMediaRequest.folder(root: root), includingPropertiesForKeys: nil).isEmpty)
    }
    func testProcessFailureTimeoutAndCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fake-engine")
        func write(_ code: String) throws { try Data(("#!/bin/sh\n" + code).utf8).write(to: script); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path) }
        try write("printf 'test result'")
        let result = try await BrowserMediaEngine.run([], timeout: 3, executable: script)
        XCTAssertEqual(result, "test result")
        try write("printf 'ERROR: Unsupported URL secret-token'; exit 1")
        do { _ = try await BrowserMediaEngine.run([], timeout: 3, executable: script); XCTFail("Expected error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("secret-token")) }
        try write("exec /bin/sleep 10")
        let start = Date()
        do { _ = try await BrowserMediaEngine.run([], timeout: 0.1, executable: script); XCTFail("Expected timeout") } catch { }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        let worker = Task { try await BrowserMediaEngine.run([], timeout: 20, executable: script) }
        try await Task.sleep(for: .milliseconds(100)); worker.cancel()
        do { _ = try await worker.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
    private func liveBundle() throws -> Bundle {
        guard let path = ProcessInfo.processInfo.environment["EASYPASTE_MEDIA_TEST_APP"],
              let bundle = Bundle(path: path) else {
            throw XCTSkip("Set EASYPASTE_MEDIA_TEST_APP to the packaged EasyPaste app")
        }
        XCTAssertTrue(BrowserMediaEngine.isAvailable(bundle: bundle))
        return bundle
    }
    private func verifyMedia(_ file: URL, mode: String, bundle: Bundle) async throws {
        let probe = try XCTUnwrap(BrowserMediaEngine.executable("ffprobe", bundle: bundle))
        let output = try await BrowserMediaEngine.run(["-v", "error", "-show_entries", "format=format_name,duration:stream=codec_type", "-of", "json", file.path], timeout: 30, executable: probe)
        let data = try XCTUnwrap(output.data(using: .utf8))
        let info = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let format = try XCTUnwrap(info["format"] as? [String: Any])
        XCTAssertTrue((format["format_name"] as? String ?? "").contains(mode == "audio" ? "mp3" : "mp4"))
        XCTAssertGreaterThan(Double(format["duration"] as? String ?? "0") ?? 0, 0)
        let streams = info["streams"] as? [[String: Any]] ?? []
        XCTAssertTrue(streams.contains { $0["codec_type"] as? String == mode })
    }
    func testBundledRuntimeIsCompleteAndNeverFallsBackToInstalledTools() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("bin/yt-dlp-runtime"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.easypaste.media", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: root))
        XCTAssertFalse(BrowserMediaEngine.isAvailable(bundle: bundle))
        XCTAssertNil(BrowserMediaEngine.executable("ffmpeg", bundle: bundle))
        for name in ["yt-dlp-runtime/yt-dlp_macos", "ffmpeg", "ffprobe", "node"] {
            let file = resources.appendingPathComponent("bin/" + name)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        XCTAssertTrue(BrowserMediaEngine.isAvailable(bundle: bundle))
        XCTAssertNil(BrowserMediaEngine.executable("../../usr/bin/true", bundle: bundle))
        let args = try BrowserMediaEngine.arguments(url: "https://example.com/media.mp4", mode: nil, bundle: bundle)
        XCTAssertTrue(args.contains("node:" + resources.appendingPathComponent("bin/node").path))
        XCTAssertTrue(args.contains(resources.appendingPathComponent("bin").path))
        XCTAssertTrue(args.contains("--no-js-runtimes")); XCTAssertTrue(args.contains("--no-plugin-dirs"))
        for name in ["ffprobe", "node"] {
            let file = resources.appendingPathComponent("bin/" + name)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            XCTAssertFalse(BrowserMediaEngine.isAvailable(bundle: bundle))
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
    }
    func testLiveDirectMP4Download() async throws {
        guard ProcessInfo.processInfo.environment["EASYPASTE_MEDIA_LIVE_TEST"] == "1" else { throw XCTSkip("Optional network test using only the packaged EasyPaste runtime") }
        let bundle = try liveBundle()
        let executable = try XCTUnwrap(BrowserMediaEngine.executable("yt-dlp", bundle: bundle))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"
        let metadata = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: nil, bundle: bundle), timeout: 60, executable: executable)
        XCTAssertFalse(try BrowserMediaEngine.metadata(metadata, mode: "video").isEmpty)
        _ = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: "video", output: root, bundle: bundle), timeout: 90, executable: executable)
        XCTAssertGreaterThan(try root.appendingPathComponent("media.mp4").resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 1000)
        try await verifyMedia(root.appendingPathComponent("media.mp4"), mode: "video", bundle: bundle)
    }
    @MainActor func testQueueCompletesInUniqueFoldersAndFailureRemovesOnlyNewFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = BrowserBridgeConfiguration(enabled: true, browser: .chrome, generation: "test")
        try BrowserExtensionFiles.write(config, to: root.appendingPathComponent("configuration.json"))
        let destination = root.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let original = destination.appendingPathComponent("original.mp4")
        try Data("original".utf8).write(to: original)
        for index in 0..<3 { _ = try BrowserMediaRequest.enqueue(url: "https://example.com/video?id=\(index)", mode: index == 2 ? "audio" : "video", config: config, root: root) }
        let model = BrowserMediaDownloads(root: root, destinationRoot: destination, revealOnRequest: false, runner: { args, _ in
            if args.contains("--dump-single-json") { return #"{"title":"Test","formats":[{"vcodec":"h264","acodec":"aac"}]}"# }
            if args.contains("mp3") { throw TextIssue(message: "Pas de piste audio") }
            let index = args.firstIndex(of: "-o")!
            try Data("video".utf8).write(to: URL(fileURLWithPath: args[index + 1].replacingOccurrences(of: "%(ext)s", with: "mp4")))
            return ""
        }, toolsAvailable: { true })
        model.consume()
        for _ in 0..<100 where model.active { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.active); XCTAssertEqual(model.jobs.count, 3)
        XCTAssertEqual(model.jobs.compactMap(\.file).count, 2)
        XCTAssertEqual(Set(model.jobs.compactMap(\.file)).count, 2)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil).count, 3)
    }
    func testLiveYouTubeVideoAndAudioDownloads() async throws {
        guard ProcessInfo.processInfo.environment["EASYPASTE_MEDIA_LIVE_TEST"] == "1" else { throw XCTSkip("Optional real YouTube download test") }
        let bundle = try liveBundle()
        let executable = try XCTUnwrap(BrowserMediaEngine.executable("yt-dlp", bundle: bundle))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        let metadata = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: nil, bundle: bundle), timeout: 90, executable: executable)
        for mode in ["video", "audio"] {
            XCTAssertFalse(try BrowserMediaEngine.metadata(metadata, mode: mode).isEmpty)
            let folder = root.appendingPathComponent(mode)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: mode, output: folder, bundle: bundle), timeout: 120, executable: executable)
            let file = folder.appendingPathComponent(mode == "audio" ? "media.mp3" : "media.mp4")
            XCTAssertGreaterThan(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 1000)
            try await verifyMedia(file, mode: mode, bundle: bundle)
        }
    }

    @MainActor func testLiveQueuedDownloadUsesBundledToolsAndReportsCompletion() async throws {
        guard ProcessInfo.processInfo.environment["EASYPASTE_MEDIA_LIVE_TEST"] == "1" else { throw XCTSkip("Optional real native bridge download") }
        let bundle = try liveBundle()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = BrowserBridgeConfiguration(enabled: true, browser: .arc, generation: "bundled-test")
        try BrowserExtensionFiles.write(config, to: root.appendingPathComponent("configuration.json"))
        _ = try BrowserMediaRequest.enqueue(url: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4", mode: "audio", config: config, root: root)
        let model = BrowserMediaDownloads(root: root, destinationRoot: root.appendingPathComponent("downloads"), revealOnRequest: false, runner: { args, timeout in
            // The production queue builds the same options with Bundle.main. For
            // XCTest only, replace the runtime locations with the packaged app.
            var options = args
            if let index = options.firstIndex(of: "--js-runtimes") { options.removeSubrange(index...index + 1) }
            if let index = options.firstIndex(of: "--ffmpeg-location") { options.removeSubrange(index...index + 1) }
            options.insert(contentsOf: ["--js-runtimes", "node:" + BrowserMediaEngine.executable("node", bundle: bundle)!.path,
                                       "--ffmpeg-location", BrowserMediaEngine.executable("ffmpeg", bundle: bundle)!.deletingLastPathComponent().path], at: options.firstIndex(of: "--")!)
            return try await BrowserMediaEngine.run(options, timeout: timeout, executable: BrowserMediaEngine.executable("yt-dlp", bundle: bundle))
        }, toolsAvailable: { BrowserMediaEngine.isAvailable(bundle: bundle) })
        model.consume()
        for _ in 0..<1800 where model.active { try await Task.sleep(for: .milliseconds(100)) }
        if model.active { await model.shutdown(); XCTFail("Download timed out") }
        XCTAssertEqual(model.jobs.count, 1)
        let job = try XCTUnwrap(model.jobs.first)
        let file = try XCTUnwrap(job.file, job.status)
        try await verifyMedia(file, mode: "audio", bundle: bundle)
        let status = try XCTUnwrap(BrowserExtensionFiles.read(BrowserMediaStatus.self, from: BrowserMediaStatus.file(job.id, root: root)))
        XCTAssertEqual(status.state, "completed")
    }

    func testProgressIsScopedToGenerationAndExpiresWithoutExposingPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), config = BrowserBridgeConfiguration(enabled: true, browser: .arc, generation: "session")
        var query: [String: Any] = ["protocol": 1, "type": "mediaStatus", "nonce": "0123456789abcdef0123456789abcdef", "extensionVersion": "0.3.0", "jobID": id.uuidString]
        func read(_ query: [String: Any], _ config: BrowserBridgeConfiguration? = config) throws -> [String: Any] {
            let reply = try BrowserMediaStatus.reply(JSONSerialization.data(withJSONObject: query), origin: BrowserBridgeProtocol.origin, config: config, root: root)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        }
        XCTAssertEqual(try read(query)["status"] as? String, "unknown")
        for state in ["queued", "preparing", "downloading", "completed", "error", "cancelled"] {
            BrowserMediaStatus.save(id, generation: "session", state: state, message: "État vérifié", root: root)
            let reply = try read(query)
            XCTAssertEqual(reply["status"] as? String, state)
            XCTAssertEqual(Set(reply.keys), Set(["protocol", "type", "nonce", "jobID", "status", "message"]))
        }
        XCTAssertEqual(try read(query, nil)["status"] as? String, "unknown")
        XCTAssertEqual(try read(query, BrowserBridgeConfiguration(enabled: true, browser: .arc, generation: "new"))["status"] as? String, "unknown")
        try BrowserExtensionFiles.write(BrowserMediaStatus(id: id, generation: "session", state: "completed", message: "Old", updated: Date().addingTimeInterval(-90000)), to: BrowserMediaStatus.file(id, root: root))
        XCTAssertEqual(try read(query)["status"] as? String, "unknown")
        query["jobID"] = "../../escape"
        XCTAssertThrowsError(try read(query))
        query["jobID"] = id.uuidString; query["path"] = "/private/file"
        XCTAssertThrowsError(try read(query))
    }

    func testQualityChoicesReachEngineAndRejectInjectedValues() throws {
        for quality in ["best", "1080", "720", "480"] {
            var value = request; value["quality"] = quality
            let parsed = try BrowserMediaRequest.validated(JSONSerialization.data(withJSONObject: value), origin: BrowserBridgeProtocol.origin)
            XCTAssertEqual(parsed.quality, quality)
            let args = try BrowserMediaEngine.arguments(url: parsed.url, mode: "video", output: URL(fileURLWithPath: "/tmp/test-quality"), quality: parsed.quality)
            let format = args[try XCTUnwrap(args.firstIndex(of: "-f")) + 1]
            XCTAssertEqual(format, quality == "best" ? "bv*+ba/b" : "bv*[height<=?\(quality)]+ba/b[height<=?\(quality)]")
        }
        var invalid = request; invalid["quality"] = "--exec"
        XCTAssertThrowsError(try BrowserMediaRequest.validated(JSONSerialization.data(withJSONObject: invalid), origin: BrowserBridgeProtocol.origin))
    }

}

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
    func testLiveDirectMP4Download() async throws {
        guard ProcessInfo.processInfo.environment["EASYPASTE_MEDIA_LIVE_TEST"] == "1" else { throw XCTSkip("Optional network test using the installed EasyMusic runtime") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"
        let metadata = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: nil), timeout: 60)
        XCTAssertFalse(try BrowserMediaEngine.metadata(metadata, mode: "video").isEmpty)
        _ = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: "video", output: root), timeout: 90)
        XCTAssertGreaterThan(try root.appendingPathComponent("media.mp4").resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 1000)
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        let metadata = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: nil), timeout: 90)
        for mode in ["video", "audio"] {
            XCTAssertFalse(try BrowserMediaEngine.metadata(metadata, mode: mode).isEmpty)
            let folder = root.appendingPathComponent(mode)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try await BrowserMediaEngine.run(BrowserMediaEngine.arguments(url: url, mode: mode, output: folder), timeout: 120)
            let file = folder.appendingPathComponent(mode == "audio" ? "media.mp3" : "media.mp4")
            XCTAssertGreaterThan(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 1000)
        }
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

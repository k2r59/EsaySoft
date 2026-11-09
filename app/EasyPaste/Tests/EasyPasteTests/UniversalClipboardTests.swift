import AppKit
import CryptoKit
import ImageIO
import XCTest
@testable import EasyPaste

@MainActor final class UniversalClipboardTests: XCTestCase {
    func testRemoteSourceIsNotAttributedToForegroundMacApp() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.declareTypes([.string, ClipboardReader.remoteType], owner: nil)
        board.setData(Data(), forType: ClipboardReader.remoteType)
        board.setString("Copié sur le téléphone", forType: .string)
        let clip = try XCTUnwrap(ClipboardReader.read(board, source: "Safari", sourceID: "com.apple.Safari", exclusions: ["com.apple.Safari"]))
        XCTAssertEqual(clip.source, "Autre appareil Apple")
        XCTAssertEqual(clip.sourceID, ClipboardReader.remoteSourceID)
        XCTAssertEqual(clip.text, "Copié sur le téléphone")
        XCTAssertNil(clip.sourceURL)
    }

    func testConfidentialAndExplicitlyExcludedRemoteSourcesStayIgnored() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        for marker in ClipboardPrivacy.forbidden {
            board.declareTypes([.string, ClipboardReader.remoteType, .init(marker)], owner: nil)
            board.setString("Texte de test", forType: .string)
            XCTAssertNil(try ClipboardReader.read(board, source: "Mac", sourceID: "test", exclusions: []))
        }
        board.declareTypes([.string, ClipboardReader.remoteType, .init("org.nspasteboard.source")], owner: nil)
        board.setString("Texte de test", forType: .string)
        board.setString("com.bitwarden.desktop", forType: .init("org.nspasteboard.source"))
        XCTAssertNil(try ClipboardReader.read(board, source: "Mac", sourceID: "test", exclusions: []))
    }

    func testPromisedRemoteTextArrivesWithoutNewOwnershipAndImportsOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let board = NSPasteboard.withUniqueName()
        defer { history.stopMonitoring(); board.releaseGlobally(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        history.enabled = true
        board.declareTypes([.string, ClipboardReader.remoteType], owner: nil)
        board.setData(Data(), forType: ClipboardReader.remoteType)
        let revision = board.changeCount
        history.poll(board)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(history.clips.isEmpty)
        board.setString("Arrivée différée", forType: .string)
        XCTAssertEqual(board.changeCount, revision, "Providing promised data does not change ownership")
        try await Task.sleep(for: .milliseconds(700))
        history.poll(board)
        for _ in 0..<100 where history.clips.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(history.clips.first?.text, "Arrivée différée")
        XCTAssertEqual(history.clips.first?.sourceID, ClipboardReader.remoteSourceID)
        let date = history.clips.first?.date
        for _ in 0..<5 { history.poll(board); try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(history.clips.count, 1)
        XCTAssertEqual(history.clips.first?.date, date)
        await history.flush()
    }

    func testRemoteImagePreservesFullResolutionAndMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let board = NSPasteboard.withUniqueName()
        defer { history.stopMonitoring(); board.releaseGlobally(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        history.enabled = true
        let png = DemoArtwork.png()
        board.declareTypes([.png, ClipboardReader.remoteType], owner: nil)
        board.setData(Data(), forType: ClipboardReader.remoteType)
        board.setData(png, forType: .png)
        history.poll(board)
        for _ in 0..<100 where history.clips.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let clip = try XCTUnwrap(history.clips.first)
        XCTAssertEqual(clip.kind, .image)
        XCTAssertNotNil(clip.imageMetadata)
        XCTAssertNil(clip.sourceURL)
        await history.flush()
        let full = try await history.fullClip(clip)
        XCTAssertEqual(full.imageData, png)
    }

    func testPauseAndNewerCopyDiscardInFlightRemoteImport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let board = NSPasteboard.withUniqueName()
        defer { history.stopMonitoring(); board.releaseGlobally(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        for pause in [true, false] {
            history.enabled = true
            board.declareTypes([.string, ClipboardReader.remoteType], owner: nil)
            board.setData(Data(), forType: ClipboardReader.remoteType)
            board.setString("Ancien transfert", forType: .string)
            history.poll(board)
            if pause { history.enabled = false }
            else { board.clearContents(); board.setString("Nouvelle copie locale", forType: .string) }
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(history.clips.isEmpty, "A stale remote import must not appear after pause or a newer copy")
        }
        XCTAssertEqual(board.string(forType: .string), "Nouvelle copie locale", "Import must never overwrite the system clipboard")
        await history.flush()
    }

    func testRemotePhotoFileIsEmbeddedAndPreviewSurvivesTemporaryFileRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = DemoArtwork.png()
        let raster = try ImageRaster.decode(png).0
        let jpeg = try XCTUnwrap(NSBitmapImageRep(cgImage: raster).representation(using: .jpeg, properties: [.compressionFactor: 0.95]))
        for (ext, data) in [("png", png), ("jpeg", jpeg)] {
            let file = directory.appendingPathComponent("photo." + ext)
            try data.write(to: file)
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.declareTypes([.fileURL, ClipboardReader.remoteType], owner: nil)
            board.setData(Data(), forType: ClipboardReader.remoteType)
            board.setString(file.absoluteString, forType: .fileURL)
            var clip = try XCTUnwrap(ClipboardReader.read(board, source: "Mac", sourceID: "test", exclusions: []))
            clip.fingerprint = Clip.fingerprint(clip.payload)
            clip.prepareThumbnail()
            try FileManager.default.removeItem(at: file)
            XCTAssertEqual(clip.kind, .image)
            XCTAssertEqual(clip.source, "Autre appareil Apple")
            XCTAssertTrue(clip.hasPreview)
            XCTAssertNotNil(clip.image)
            XCTAssertNotNil(clip.previewImage(maxPixels: 1600))
            XCTAssertEqual(clip.imageMetadata?.width, raster.width)
            XCTAssertEqual(clip.imageMetadata?.height, raster.height)
            XCTAssertFalse(clip.payload.representations.flatMap { $0 }.contains { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue })
            if ext == "png" { XCTAssertEqual(clip.imageData, png) }
        }
    }

    func testRemotePhotoWaitsForFileButLocalFinderCopiesRemainFiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpeg")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.declareTypes([.fileURL, ClipboardReader.remoteType], owner: nil)
        board.setString(file.absoluteString, forType: .fileURL)
        XCTAssertNil(try ClipboardReader.read(board, source: "Mac", sourceID: "test", exclusions: []))
        board.declareTypes([.fileURL], owner: nil)
        board.setString(file.absoluteString, forType: .fileURL)
        XCTAssertEqual(try ClipboardReader.read(board, source: "Finder", sourceID: "com.apple.finder", exclusions: [])?.kind, .file)
    }

    func testRemotePhotoRejectsDisguisedSVGAndOversizedFiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpeg")
        defer { try? FileManager.default.removeItem(at: file) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.declareTypes([.fileURL, ClipboardReader.remoteType], owner: nil)
        board.setString(file.absoluteString, forType: .fileURL)
        try Data("<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>".utf8).write(to: file)
        XCTAssertThrowsError(try ClipboardReader.read(board, source: "Mac", sourceID: "test", exclusions: []))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ClipboardReader.limit + 1))
        try handle.close()
        XCTAssertThrowsError(try ClipboardReader.read(board, source: "Mac", sourceID: "test", exclusions: []))
    }

    func testDeniedRemotePhotoRetainsFileInsteadOfLosingCopy() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpeg")
        try Data("fixture".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: file)
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.declareTypes([.fileURL, ClipboardReader.remoteType], owner: nil)
        board.setString(file.absoluteString, forType: .fileURL)
        let clip = try XCTUnwrap(ClipboardReader.read(board, source: "Mac", sourceID: "test", exclusions: []))
        XCTAssertEqual(clip.kind, .file)
        XCTAssertEqual(clip.text, file.path)
        XCTAssertEqual(clip.source, "Autre appareil Apple")
    }

    func testHandoffFolderScopeRejectsSiblingsTraversalAndSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("shared-pasteboard")
        let other = directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(HandoffPhotoAccess.contains(root.appendingPathComponent("items/test/photo.jpg"), in: root))
        XCTAssertFalse(HandoffPhotoAccess.contains(root, in: root))
        XCTAssertFalse(HandoffPhotoAccess.contains(directory.appendingPathComponent("shared-pasteboard-other/photo.jpg"), in: root))
        XCTAssertFalse(HandoffPhotoAccess.contains(root.appendingPathComponent("../other/photo.jpg"), in: root))
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        XCTAssertFalse(HandoffPhotoAccess.contains(link.appendingPathComponent("photo.jpg"), in: root))
        XCTAssertFalse(HandoffPhotoAccess.contains(URL(string: "https://example.com/photo.jpg")!, in: root))
    }

    func testPermissionPanelRejectsBroaderFolderBeforeAccepting() throws {
        let validator = HandoffFolderValidator()
        XCTAssertNoThrow(try validator.panel(NSObject(), validate: HandoffPhotoAccess.transferDirectory))
        XCTAssertThrowsError(try validator.panel(NSObject(), validate: FileManager.default.homeDirectoryForCurrentUser))
        XCTAssertThrowsError(try validator.panel(NSObject(), validate: HandoffPhotoAccess.transferDirectory.deletingLastPathComponent()))
    }

    func testPhotoAccessNeverCreatesPermissionAndForgetOnlyRemovesItsBookmark() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("keep", forKey: "otherPreference")
        let access = HandoffPhotoAccess(defaults: defaults)
        XCTAssertFalse(access.configured)
        let photo = HandoffPhotoAccess.transferDirectory.appendingPathComponent("items/test/photo.jpg")
        XCTAssertEqual(access.withAccess(to: photo) { 42 }, 42)
        XCTAssertFalse(access.configured)
        defaults.set(Data("invalid bookmark".utf8), forKey: HandoffPhotoAccess.bookmarkKey)
        XCTAssertEqual(access.withAccess(to: photo) { 43 }, 43)
        access.forget()
        XCTAssertFalse(access.configured)
        XCTAssertEqual(defaults.string(forKey: "otherPreference"), "keep")
    }

    func testRetryBackoffIsBoundedAndNeverAppliesToAnotherRevision() {
        var retry = ClipboardRetry()
        var now = Date(timeIntervalSince1970: 100)
        retry.unavailable(10, now: now)
        XCTAssertFalse(retry.isDue(10, now: now))
        now += 1
        XCTAssertTrue(retry.isDue(10, now: now))
        XCTAssertFalse(retry.isDue(11, now: now))
        for _ in 0..<8 { retry.unavailable(10, now: now); now += 10 }
        XCTAssertFalse(retry.isDue(10, now: now.addingTimeInterval(1000)))
        retry.unavailable(11, now: now)
        XCTAssertEqual(retry.attempts, 1)
        XCTAssertTrue(retry.isDue(11, now: now.addingTimeInterval(1)))
        retry.clear()
        XCTAssertFalse(retry.isDue(11, now: now.addingTimeInterval(1000)))
    }
}

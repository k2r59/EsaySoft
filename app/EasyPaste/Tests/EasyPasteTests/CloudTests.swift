import XCTest
import CryptoKit
import AppKit
@testable import EasyPaste

final class CloudRepositoryTests: XCTestCase {
    private var root: URL!
    private var a: ClipVault!
    private var b: ClipVault!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-cloud-tests-" + UUID().uuidString)
        a = try ClipVault(directory: root.appendingPathComponent("MacA"), key: SymmetricKey(size: .bits256))
        b = try ClipVault(directory: root.appendingPathComponent("MacB"), key: SymmetricKey(size: .bits256))
    }
    override func tearDownWithError() throws {
        for vault in [a, b] { if let vault, FileManager.default.fileExists(atPath: vault.playbackDirectory.path) { try FileManager.default.removeItem(at: vault.playbackDirectory) } }
        try FileManager.default.removeItem(at: root)
    }
    @discardableResult private func transfer(_ key: CloudKey, from source: ClipVault, to destination: ClipVault) throws -> CloudHeader {
        let asset = try XCTUnwrap(source.prepareCloudContent(key, uploadedMovie: nil))
        defer { try? FileManager.default.removeItem(at: asset.directory) }
        return try destination.applyCloud(asset.header, contentURL: asset.content, movieURL: asset.movie)
    }
    func testRichTextOriginalBytesAndMetadataSurviveDifferentLocalKeys() throws {
        var clip = makeClip("Texte français éàœ")
        clip.payload.representations[0].append(.init(type: NSPasteboard.PasteboardType.rtf.rawValue, data: Data("{\\rtf1\\ansi Texte \\b gras}".utf8)))
        clip.pinned = true; clip.ocr = "Reconnaissance"; clip.parentID = UUID()
        try a.save(clip); try transfer(CloudKey(.clip, clip.id), from: a, to: b)
        let received = try XCTUnwrap(b.load().first)
        XCTAssertEqual(received.payload, clip.payload); XCTAssertEqual(received.ocr, clip.ocr)
        XCTAssertTrue(received.pinned); XCTAssertEqual(received.parentID, clip.parentID)
        XCTAssertNotEqual(try Data(contentsOf: a.directory.appendingPathComponent(clip.id.uuidString + ".clip")), try Data(contentsOf: b.directory.appendingPathComponent(clip.id.uuidString + ".clip")))
    }
    func testLegacyRecordsHaveStableInventoryAndRemainReadable() throws {
        let clip = makeClip("Ancien historique")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        object.removeValue(forKey: "cloudRevision")
        let legacy = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: object))
        try a.write(legacy, name: clip.id.uuidString + ".clip")
        let board = Pinboard(name: "Ancienne collection", color: 2)
        try a.write([board], name: "boards.json.enc")
        for header in try a.cloudInventory() {
            XCTAssertEqual(try a.cloudHeader(header.key), header)
            try transfer(header.key, from: a, to: b)
        }
        XCTAssertEqual(try b.load().first?.text, clip.text); XCTAssertEqual(try b.loadBoards().first?.name, board.name)
    }
    func testConcurrentEditsConvergeAndOlderDownloadsNeverOverwrite() throws {
        let clip = makeClip("Initial"); let key = CloudKey(.clip, clip.id)
        try a.save(clip); try transfer(key, from: a, to: b)
        var left = try XCTUnwrap(a.load().first), right = try XCTUnwrap(b.load().first)
        left.title = "Mac A"; right.title = "Mac B"; try a.save(left); try b.save(right)
        let first = try XCTUnwrap(a.prepareCloudContent(key, uploadedMovie: nil))
        let second = try XCTUnwrap(b.prepareCloudContent(key, uploadedMovie: nil))
        let winner = max(first.header.revision, second.header.revision)
        _ = try b.applyCloud(first.header, contentURL: first.content, movieURL: nil)
        _ = try a.applyCloud(second.header, contentURL: second.content, movieURL: nil)
        XCTAssertEqual(try a.cloudHeader(key)?.revision, winner); XCTAssertEqual(try b.cloudHeader(key)?.revision, winner)
        XCTAssertEqual(try a.load().first?.title, try b.load().first?.title)
        XCTAssertEqual(try transfer(key, from: a, to: b), try a.cloudHeader(key))
    }
    func testPermanentDeletionBeatsOfflineEditAndSurvivesRestart() throws {
        let clip = makeClip("À supprimer"); let key = CloudKey(.clip, clip.id)
        try a.save(clip); try transfer(key, from: a, to: b)
        let stale = try XCTUnwrap(b.prepareCloudContent(key, uploadedMovie: nil))
        try a.delete(clip.id)
        var offline = try XCTUnwrap(b.load().first); offline.title = "Édition hors ligne"; try b.save(offline)
        try transfer(key, from: a, to: b)
        XCTAssertTrue(try a.load().isEmpty); XCTAssertTrue(try b.load().isEmpty)
        let result = try b.applyCloud(stale.header, contentURL: stale.content, movieURL: nil)
        XCTAssertTrue(result.deleted)
        try b.save(offline); XCTAssertTrue(try b.load().isEmpty)
        XCTAssertEqual(try a.cloudInventory().first?.deleted, true)
    }
    func testTrashAndRestoreSyncBeforePermanentDeletion() throws {
        var clip = makeClip("Corbeille"); let key = CloudKey(.clip, clip.id)
        clip.trashedAt = Date(); try a.save(clip); try transfer(key, from: a, to: b)
        XCTAssertNotNil(try b.load().first?.trashedAt)
        var restore = try XCTUnwrap(b.load().first); restore.trashedAt = nil; try b.save(restore)
        try transfer(key, from: b, to: a); XCTAssertNil(try a.load().first?.trashedAt)
    }
    func testCollectionDoesNotGrantMCPAccessAndKeepsLocalConsent() throws {
        let board = Pinboard(name: "Collection", color: 1, shared: true); let key = CloudKey(.board, board.id)
        try a.saveBoards([board]); try transfer(key, from: a, to: b)
        XCTAssertFalse(try XCTUnwrap(b.loadBoards().first).shared)
        var local = try XCTUnwrap(b.loadBoards().first); local.shared = true; try b.saveBoards([local])
        var renamed = try XCTUnwrap(a.loadBoards().first); renamed.name = "Renommée"; renamed.shared = false
        try a.saveBoards([renamed]); try transfer(key, from: a, to: b)
        XCTAssertTrue(try XCTUnwrap(b.loadBoards().first).shared)
        XCTAssertEqual(try b.loadBoards().first?.name, "Renommée")
    }
    func testStaleCollectionUICannotDeleteNewRemoteCollectionOrRename() throws {
        let first = Pinboard(name: "Initiale", color: 0), remote = Pinboard(name: "Autre Mac", color: 1)
        try a.saveBoards([first]); let snapshot = try a.loadBoards()
        try b.saveBoards([remote]); try transfer(CloudKey(.board, remote.id), from: b, to: a)
        var renamed = try XCTUnwrap(a.loadBoards().first(where: { $0.id == first.id })); renamed.name = "Nom distant"
        try a.saveBoards([renamed, remote])
        var oldUI = snapshot; oldUI[0].shared = true
        try a.saveBoards(oldUI, replacing: snapshot)
        let boards = try a.loadBoards()
        XCTAssertEqual(boards.count, 2); XCTAssertEqual(boards.first(where: { $0.id == first.id })?.name, "Nom distant")
        XCTAssertTrue(boards.first(where: { $0.id == first.id })?.shared == true)
    }
    func testDeletedCollectionDoesNotReturnThroughOfflineMembership() throws {
        let board = Pinboard(name: "Projet", color: 0); var clip = makeClip("Note"); clip.boards = [board.id]
        try a.saveBoards([board]); try a.save(clip)
        try transfer(CloudKey(.board, board.id), from: a, to: b); try transfer(CloudKey(.clip, clip.id), from: a, to: b)
        try a.saveBoards([]); try transfer(CloudKey(.board, board.id), from: a, to: b)
        XCTAssertTrue(try b.loadBoards().isEmpty); XCTAssertTrue(try XCTUnwrap(b.load().first).boards.isEmpty)
    }
    func testFinderReferencesStayLocal() throws {
        var clip = makeClip("/private/local.pdf"); clip.kind = .file
        try a.save(clip)
        XCTAssertTrue(try a.cloudInventory().isEmpty)
        XCTAssertNil(try a.prepareCloudContent(CloudKey(.clip,clip.id), uploadedMovie: nil))
        XCTAssertEqual(try a.load().count, 1)
    }
    func testVideosUseOriginalBytesAndMetadataEditsReuseMedia() throws {
        var clip = makeClip(""); clip.kind = .video; clip.payload = .init(representations: []); clip.duration = 7
        let original = Data(repeating: 0x63, count: MediaVault.chunkSize * 3 + 71), movie = root.appendingPathComponent("original.mp4")
        try original.write(to: movie); clip.storedBytes = try a.importVideo(movie, id: clip.id); try a.save(clip)
        let key = CloudKey(.clip,clip.id)
        try transfer(key, from: a, to: b)
        XCTAssertEqual(try Data(contentsOf: b.videoURL(clip.id)), original)
        let firstCipher = try Data(contentsOf: b.mediaURL(clip.id))
        var pinned = try XCTUnwrap(a.load().first); pinned.pinned = true; try a.save(pinned)
        let asset = try XCTUnwrap(a.prepareCloudContent(key, uploadedMovie: clip.fingerprint))
        XCTAssertNil(asset.movie)
        _ = try b.applyCloud(asset.header, contentURL: asset.content, movieURL: nil)
        XCTAssertTrue(try XCTUnwrap(b.load().first).pinned)
        XCTAssertEqual(try Data(contentsOf: b.mediaURL(clip.id)), firstCipher)
        XCTAssertThrowsError(try ClipVault(directory: root.appendingPathComponent("MacC"), key: SymmetricKey(size: .bits256)).applyCloud(asset.header, contentURL: asset.content, movieURL: nil))
    }
    func testMalformedOrFutureRemoteDataDoesNotReplaceLocalRecord() throws {
        let clip = makeClip("Conserver"); let key = CloudKey(.clip, clip.id); try a.save(clip)
        var header = try XCTUnwrap(a.cloudHeader(key)); header.revision = .next(after: header.revision)
        let url = root.appendingPathComponent("invalid.json"); try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try a.applyCloud(header, contentURL: url, movieURL: nil))
        header.format = 2; XCTAssertThrowsError(try a.applyCloud(header, contentURL: url, movieURL: nil))
        XCTAssertEqual(try a.load().first?.text, clip.text)
    }
    func testNegativeOrExcessiveRemoteSizeIsRejectedBeforeAllocation() throws {
        var clip = makeClip("Invalide"); let key = CloudKey(.clip,clip.id)
        let header = CloudHeader(key: key, revision: .next()); clip.cloudRevision = header.revision
        let url = root.appendingPathComponent("content.json")
        for size in [-1, Int.max] {
            clip.storedBytes = size
            try JSONEncoder().encode(CloudContent(clip: clip)).write(to: url)
            XCTAssertThrowsError(try a.applyCloud(header, contentURL: url, movieURL: nil))
        }
        XCTAssertTrue(try a.load().isEmpty)
    }
    func testCheckpointRejectsStaleWritesAndStagingIsIsolated() throws {
        try a.saveCloudCheckpoint(.init(sequence: 2, account: "new")); try a.saveCloudCheckpoint(.init(sequence: 1, account: "old"))
        XCTAssertEqual(try a.cloudCheckpoint().account, "new")
        let clip = makeClip("Test"); try a.save(clip); try b.save(clip)
        let first = try XCTUnwrap(a.prepareCloudContent(CloudKey(.clip,clip.id), uploadedMovie: nil))
        let second = try XCTUnwrap(b.prepareCloudContent(CloudKey(.clip,clip.id), uploadedMovie: nil))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: first.directory.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: XCTUnwrap(first.content).path)[.posixPermissions] as? Int, 0o600)
        try a.cleanCloudStaging(); XCTAssertFalse(FileManager.default.fileExists(atPath: first.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.directory.path))
    }
    func testRevisionSurvivesClockMovingBackwards() {
        let old = CloudRevision(date: Date(timeIntervalSince1970: 10_000), nonce: "A")
        let next = CloudRevision.next(after: old, now: Date(timeIntervalSince1970: 100))
        XCTAssertGreaterThan(next, old)
        XCTAssertGreaterThan(CloudRevision(date: old.date, nonce: "B"), old)
    }
}

@MainActor final class CloudLocalModeTests: XCTestCase {
    func testReceivedChangesRefreshWithoutLosingLocalCollectionEdits() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-cloud-refresh-" + UUID().uuidString)
        let suite = "EasyPaste-refresh-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: folder); defaults.removePersistentDomain(forName: suite) }
        let vault = try ClipVault(directory: folder.appendingPathComponent("local"), key: SymmetricKey(size: .bits256))
        let remote = try ClipVault(directory: folder.appendingPathComponent("remote"), key: SymmetricKey(size: .bits256))
        let board = Pinboard(name: "Locale", color: 0)
        try vault.saveBoards([board])
        let history = History(vault: vault, monitor: false, defaults: defaults)
        defer { history.stopMonitoring() }
        let note = makeClip("À garder"); history.add(note); await history.flush()
        let incoming = Pinboard(name: "Depuis un autre Mac", color: 2)
        try remote.saveBoards([incoming])
        let asset = try XCTUnwrap(remote.prepareCloudContent(CloudKey(.board,incoming.id), uploadedMovie: nil))
        _ = try vault.applyCloud(asset.header, contentURL: asset.content, movieURL: nil)
        history.scheduleCloudReload()
        history.renameBoard(board.id, name: "Modification locale")
        history.mutate(note.id) { $0.pinned = true }
        await history.flush()
        for _ in 0..<100 {
            if history.boards.contains(where: { $0.id == incoming.id }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(history.boards.count, 2)
        XCTAssertEqual(history.boards.first(where: { $0.id == board.id })?.name, "Modification locale")
        XCTAssertTrue(try XCTUnwrap(history.clips.first).pinned)
        XCTAssertEqual(try vault.load().first?.payload, note.payload)
    }
    func testUnsignedDemoNeverCreatesCloudContainerEvenWithSavedEnabledPreference() async {
        let name = "EasyPaste-Cloud-" + UUID().uuidString
        let isolated = UserDefaults(suiteName: name)!
        defer { isolated.removePersistentDomain(forName: name) }
        isolated.set(true, forKey: "iCloudEnabled")
        let cloud = CloudSync(defaults: isolated, allowed: false)
        XCTAssertFalse(cloud.enabled); XCTAssertFalse(cloud.available)
        await cloud.setEnabled(true); XCTAssertFalse(cloud.enabled)
    }
}

import AppKit
import CryptoKit
import XCTest
@testable import EasyPaste

@MainActor final class PasteUsageTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var vault: ClipVault!
    private var history: History!
    private var links: [Clip] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "EasyPaste.paste-usage." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        vault = try ClipVault(directory: directory, key: SymmetricKey(size: .bits256))
        history = History(vault: vault, monitor: false, defaults: defaults)
        links = (1...5).map { makeClip("https://example.com/link-\($0)") }
        for clip in links { history.add(clip) }
        await history.flush()
    }

    override func tearDown() async throws {
        history.stopMonitoring(); await history.flush()
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
        history = nil; vault = nil; links = []
    }

    func testDefaultEnabledAndPreferenceSurvivesRestartWithoutErasingCounts() async {
        XCTAssertTrue(history.showPasteCounts)
        history.recordPaste([links[0]])
        history.showPasteCounts = false
        history.recordPaste([links[0]])
        await history.flush()
        let reloaded = History(vault: vault, monitor: false, defaults: defaults)
        XCTAssertFalse(reloaded.showPasteCounts)
        XCTAssertEqual(reloaded.pasteUsage.count(for: links[0].id), 2)
        reloaded.showPasteCounts = true
        XCTAssertTrue(defaults.bool(forKey: "showPasteCounts"))
    }

    func testFiveLinksTrackOnlyPastedItemsAndDeduplicateEachBatch() async throws {
        let selected = history.selected
        history.recordPaste([links[1], links[3], links[1]])
        history.recordPaste([links[1]])
        XCTAssertEqual(links.map { history.pasteUsage.count(for: $0.id) }, [0, 2, 0, 1, 0])
        XCTAssertEqual(history.selected, selected, "Recording usage must not move selection or reset search")
        await history.flush()
        XCTAssertEqual(try vault.loadPasteUsage(), history.pasteUsage)
        let reloaded = History(vault: vault, monitor: false, defaults: defaults)
        XCTAssertEqual(links.map { reloaded.pasteUsage.count(for: $0.id) }, [0, 2, 0, 1, 0])
    }

    func testCopySelectionPreviewAndStackCopyDoNotCountAsPastes() async throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        history.select(links[0]); history.openPreview(links[0]); history.queue(links[0])
        let copied = await history.copy([links[0]], to: pb)
        XCTAssertTrue(copied)
        let plainCopied = await history.copy([links[1], links[2]], plain: true, to: pb)
        XCTAssertTrue(plainCopied)
        XCTAssertTrue(history.pasteUsage.counts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(ClipVault.pasteUsageFile).path))
        history.shelfPreview = nil; history.previewing = nil
    }

    func testCountersUseSeparateEncryptedIndexWithoutRewritingPayloads() async throws {
        let original = try Dictionary(uniqueKeysWithValues: links.map { clip in
            (clip.id, try Data(contentsOf: directory.appendingPathComponent(clip.id.uuidString + ".clip")))
        })
        history.recordPaste(links)
        await history.flush()
        for clip in links {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(clip.id.uuidString + ".clip")), original[clip.id])
        }
        let file = directory.appendingPathComponent(ClipVault.pasteUsageFile)
        let raw = try Data(contentsOf: file)
        XCTAssertNil(raw.range(of: Data(links[0].id.uuidString.utf8)))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try vault.loadPasteUsage().count(for: links[0].id), 1)
    }

    func testRepeatedClipboardImportKeepsCountButNewCardStartsAtZero() async {
        history.recordPaste([links[0]])
        let duplicate = makeClip(links[0].text)
        history.add(duplicate)
        let current = history.clips.first { $0.fingerprint == duplicate.fingerprint }!
        XCTAssertEqual(current.id, links[0].id)
        XCTAssertEqual(history.pasteUsage.count(for: current.id), 1)
        history.add(makeClip("https://example.com/new-link"))
        XCTAssertEqual(history.pasteUsage.count(for: history.selected!), 0)
    }

    func testStaleChangedTrashedAndUnknownCardsCannotIncrement() async {
        history.recordPaste([links[0]])
        history.trash(links[0])
        history.edit(links[1].id, title: "Nouveau", text: "different", rtf: nil)
        history.recordPaste([links[0], links[1], makeClip("Absent")])
        XCTAssertEqual(history.pasteUsage.count(for: links[0].id), 1)
        XCTAssertEqual(history.pasteUsage.count(for: links[1].id), 0)
        history.restore(links[0])
        history.recordPaste([links[0]])
        XCTAssertEqual(history.pasteUsage.count(for: links[0].id), 2)
    }

    func testPlainBatchCountsOnlyNonemptyTextContributorsAndStackKeepsCounts() async {
        var image = makeClip(""); image.kind = .image
        history.add(image)
        history.queue(links[0]); history.queue(links[1])
        history.recordPaste([image, links[0], links[1]], plain: true)
        history.consumeStack([links[0]])
        XCTAssertEqual(history.pasteUsage.count(for: image.id), 0)
        XCTAssertEqual(history.pasteUsage.count(for: links[0].id), 1)
        XCTAssertEqual(history.pasteUsage.count(for: links[1].id), 1)
        XCTAssertEqual(history.stack, [links[1].id])
    }

    func testRichTextBatchDoesNotCountAnEmptyContribution() async {
        let empty = makeClip("")
        history.add(empty)
        history.recordPaste([empty, links[0]])
        XCTAssertEqual(history.pasteUsage.count(for: empty.id), 0)
        XCTAssertEqual(history.pasteUsage.count(for: links[0].id), 1)
    }

    func testPermanentDeletionPurgesUsageButTrashRestorePreservesIt() async throws {
        history.recordPaste([links[0], links[1]])
        history.trash(links[0]); history.restore(links[0])
        XCTAssertEqual(history.pasteUsage.count(for: links[0].id), 1)
        history.trash(links[0])
        let trashed = try XCTUnwrap(history.clips.first { $0.id == links[0].id })
        history.permanentlyDelete([trashed])
        for _ in 0..<100 where history.clips.contains(where: { $0.id == links[0].id }) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(history.clips.contains { $0.id == links[0].id })
        await history.flush()
        XCTAssertEqual(try vault.loadPasteUsage().count(for: links[0].id), 0)
        XCTAssertEqual(try vault.loadPasteUsage().count(for: links[1].id), 1)
    }

    func testLegacyHistoryLoadsWithoutCounterFileAndCorruptionDoesNotBlockHistory() async throws {
        XCTAssertTrue(try vault.loadPasteUsage().counts.isEmpty)
        let file = directory.appendingPathComponent(ClipVault.pasteUsageFile)
        let invalid = Data("damaged encrypted counter index".utf8)
        try invalid.write(to: file)
        let reloaded = History(vault: vault, monitor: false, defaults: defaults)
        XCTAssertFalse(reloaded.fault)
        XCTAssertEqual(reloaded.clips.count, 5)
        reloaded.recordPaste([links[0]])
        await reloaded.flush()
        XCTAssertEqual(try Data(contentsOf: file), invalid, "Never overwrite an unreadable optional index")
        XCTAssertTrue(reloaded.pasteUsage.counts.isEmpty)
    }

    func testCounterSaturatesAndInvalidValuesAreNormalized() throws {
        let id = UUID()
        let raw = try JSONSerialization.data(withJSONObject: ["counts": [id.uuidString, Int.max]])
        var usage = try JSONDecoder().decode(PasteUsage.self, from: raw)
        usage.record([id]); XCTAssertEqual(usage.count(for: id), Int.max)
        let negative = try JSONSerialization.data(withJSONObject: ["counts": [id.uuidString, -3]])
        usage = try JSONDecoder().decode(PasteUsage.self, from: negative)
        XCTAssertEqual(usage.count(for: id), 0)
        usage.record([id]); XCTAssertEqual(usage.count(for: id), 1)
        usage.retain([]); XCTAssertTrue(usage.counts.isEmpty)
    }
}

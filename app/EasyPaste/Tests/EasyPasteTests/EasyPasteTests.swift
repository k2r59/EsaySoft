import XCTest
import AppKit
import CryptoKit
@testable import EasyPaste

final class VaultTests: XCTestCase {
    var folder: URL!
    var vault: ClipVault!
    override func setUpWithError() throws { folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-tests-" + UUID().uuidString); vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256)) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func testEncryptedRoundtripMetadataAndTamper() throws {
        let clip = makeClip("Un secret de test à chiffrer")
        try vault.save(clip)
        let url = folder.appendingPathComponent(clip.id.uuidString + ".clip")
        var raw = try Data(contentsOf: url)
        XCTAssertNil(raw.range(of: Data(clip.text.utf8)))
        XCTAssertEqual(try vault.read(Clip.self, name: url.lastPathComponent).payload, clip.payload)
        let metadata = try XCTUnwrap(vault.load(metadataOnly: true).first)
        XCTAssertTrue(metadata.payload.representations.isEmpty)
        XCTAssertEqual(metadata.byteCount, clip.byteCount)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
        raw[raw.count-1] ^= 0xFF; try raw.write(to: url)
        XCTAssertThrowsError(try vault.read(Clip.self, name: url.lastPathComponent))
    }
    func testWrongKeyDoesNotReplaceHistory() throws {
        let clip = makeClip("Clé différente"); try vault.save(clip)
        let other = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try other.load())
        XCTAssertEqual(try vault.load().first?.text, clip.text)
    }
    func testMCPRequiresOptInAndSharedCollection() throws {
        var privateClip = makeClip("Privé"); var shared = makeClip("Autorisé"); var trashed = makeClip("Supprimé")
        let board = Pinboard(name: "Partagée", color: 0, shared: true)
        privateClip.boards = [UUID()]; shared.boards = [board.id]; trashed.boards = [board.id]; trashed.trashedAt = Date()
        try vault.write([board], name: "boards.json.enc"); for clip in [privateClip, shared, trashed] { try vault.save(clip) }
        let disabled = MCPService(enabled: { false }, vault: { XCTFail("Must not open keychain while disabled"); return self.vault })
        XCTAssertNotNil(disabled.reply(call("search_clips"))?["error"])
        let service = MCPService(enabled: { true }, vault: { self.vault })
        let response = try XCTUnwrap(service.reply(call("search_clips")))
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        XCTAssertTrue(serialized.contains("Autorisé")); XCTAssertFalse(serialized.contains("Privé")); XCTAssertFalse(serialized.contains("Supprimé"))
        XCTAssertNotNil(service.reply(call("read_clip", ["id": privateClip.id.uuidString]))?["error"])
        XCTAssertNotNil(service.reply(call("read_clip", ["id": "../../secret"]))?["error"])
        try vault.write([Pinboard(id: board.id, name: board.name, color: 0, shared: false)], name: "boards.json.enc")
        XCTAssertNotNil(service.reply(call("read_clip", ["id": shared.id.uuidString]))?["error"])
        XCTAssertNil(service.reply(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    }
    private func call(_ name: String, _ args: [String: Any] = [:]) -> [String: Any] { ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": args]] }
}
@MainActor final class HistoryTests: XCTestCase {
    func testDedupEditAndCopyPreservePayloadAndCollections() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-history-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: defaults)
        let c = makeClip("Bonjour français")
        history.add(c); history.togglePin(c); history.addBoard("Modèles")
        history.toggleBoard(c, try XCTUnwrap(history.boards.first))
        history.add(makeClip("Bonjour français")); await history.flush()
        XCTAssertEqual(history.clips.count, 1)
        let saved = try XCTUnwrap(vault.load().first)
        XCTAssertEqual(saved.id, c.id); XCTAssertTrue(saved.pinned); XCTAssertEqual(saved.boards.count, 1)
        XCTAssertEqual(saved.payload, c.payload)
        let edited = try await history.saveEditedText("Merci !", title: "Ma réponse", rtf: nil, original: c)
        await history.flush()
        XCTAssertEqual(try vault.read(Clip.self, name: edited.id.uuidString + ".clip").text, "Merci !")
        XCTAssertNotEqual(edited.id, c.id); XCTAssertEqual(try vault.read(Clip.self, name: c.id.uuidString + ".clip").payload, c.payload)
        XCTAssertEqual(history.clips.first?.byteCount, Data("Merci !".utf8).count)
        let pb = NSPasteboard(name: .init("EasyPaste-test-" + UUID().uuidString)); defer { pb.releaseGlobally() }
        let ok = await history.copy([edited], to: pb)
        XCTAssertTrue(ok); XCTAssertEqual(pb.string(forType: .string), "Merci !")
        history.trash(c); await history.flush(); XCTAssertNotNil(try vault.read(Clip.self, name: c.id.uuidString + ".clip").trashedAt)
        history.restore(c); await history.flush(); XCTAssertNil(try vault.read(Clip.self, name: c.id.uuidString + ".clip").trashedAt)
        defaults.set(true, forKey: "monitoring"); history.stopMonitoring()
        XCTAssertTrue(defaults.bool(forKey: "monitoring"))
    }
    func testNamedPasteboardPrivacyFilesAndRichText() throws {
        let pb = NSPasteboard(name: .init("EasyPaste-test-" + UUID().uuidString)); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem(); item.setString("secret", forType: .string); item.setString("1", forType: .init("org.nspasteboard.ConcealedType"))
        pb.writeObjects([item])
        XCTAssertNil(try ClipboardReader.read(pb, source: "Test", sourceID: "test", exclusions: []))
        pb.clearContents(); pb.setString("secret", forType: .string)
        XCTAssertNil(try ClipboardReader.read(pb, source: "Test", sourceID: "com.1password.1password", exclusions: []))
        XCTAssertNil(try ClipboardReader.read(pb, source: "Test", sourceID: "test", exclusions: ["test"]))
        pb.clearContents()
        let rtf = NSAttributedString(string: "Bonjour riche").rtf(from: NSRange(location: 0, length: 13), documentAttributes: [:])!
        pb.setData(rtf, forType: .rtf)
        XCTAssertEqual(try ClipboardReader.read(pb, source: "Test", sourceID: "test", exclusions: [])?.text, "Bonjour riche")
        pb.clearContents(); pb.writeObjects([URL(fileURLWithPath: "/tmp/mon document.pdf") as NSURL])
        let file = try XCTUnwrap(ClipboardReader.read(pb, source: "Finder", sourceID: "com.apple.finder", exclusions: []))
        XCTAssertEqual(file.kind, .file); XCTAssertEqual(file.title, "mon document.pdf"); XCTAssertEqual(file.text, "/tmp/mon document.pdf")
    }
    func testImageThumbnailAndBackgroundOCR() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let testImage = NSImage(size: NSSize(width: 1000, height: 400)); testImage.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0,y: 0,width: 1000,height: 400).fill()
        "PRENDRE LE LARGE".draw(at: NSPoint(x: 60,y: 170), withAttributes: [.font: NSFont.systemFont(ofSize: 70), .foregroundColor: NSColor.black])
        testImage.unlockFocus()
        let data = NSBitmapImageRep(data: testImage.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.png.rawValue, data: data)]])
        var image = Clip(title: "Image de test", text: "", source: "Test", sourceID: "test", kind: .image, fingerprint: Clip.fingerprint(payload), payload: payload)
        image.prepareThumbnail()
        let bitmap = try XCTUnwrap(image.thumbnail.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertLessThanOrEqual(max(bitmap.pixelsWide, bitmap.pixelsHigh), 640)
        let recognized = try await Task.detached { try ImageText.recognize(data) }.value
        XCTAssertTrue(recognized.localizedCaseInsensitiveContains("large"), "Direct OCR: \(recognized)")
        history.add(image)
        for _ in 0..<100 {
            if history.clips.first?.ocr.localizedCaseInsensitiveContains("large") == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await history.flush()
        XCTAssertTrue(history.clips.first?.ocr.localizedCaseInsensitiveContains("large") == true, "OCR: \(history.clips.first?.ocr ?? "vide")")
        XCTAssertEqual(try vault.load().first?.imageData, data, "The full original must remain intact")
    }
    func testDeselectingOneCardNeverDeletesItInsteadOfTheRemainingSelection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let a = makeClip("Sélectionnée"); let b = makeClip("Désélectionnée")
        history.add(a); history.add(b); await history.flush()
        for _ in 0..<50 { if history.visible.count == 2 { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        history.select(a); history.select(b, modifiers: .command)
        XCTAssertEqual(Set(history.selection.map(\.id)), Set([a.id,b.id]))
        history.select(b, modifiers: .command)
        XCTAssertEqual(history.selection.map(\.id), [a.id]); XCTAssertEqual(history.selected, a.id)
        history.trashItems(history.selection); await history.flush()
        XCTAssertNotNil(try vault.load().first { $0.id == a.id }?.trashedAt)
        XCTAssertNil(try vault.load().first { $0.id == b.id }?.trashedAt)
    }
    func testPermanentDeletionOnlyRemovesChosenTrashedItems() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let a = makeClip("À supprimer"); let b = makeClip("À restaurer"); let c = makeClip("À garder")
        for clip in [a,b,c] { history.add(clip) }; history.trashItems([a,b]); await history.flush()
        let trash = try vault.load().filter { $0.id == a.id }
        history.permanentlyDelete(trash + [c]); await history.flush()
        XCTAssertEqual(Set(try vault.load().map(\.id)), Set([b.id, c.id]))
        XCTAssertNotNil(try vault.load().first { $0.id == b.id }?.trashedAt)
        XCTAssertNil(try vault.load().first { $0.id == c.id }?.trashedAt)
    }
    func testRetentionKeepsFavoritesAndCollections() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        var old = makeClip("Ordinaire"); old.date = Date().addingTimeInterval(-10*86400)
        var favorite = makeClip("Favori"); favorite.date = old.date; favorite.pinned = true
        var collected = makeClip("Collection"); collected.date = old.date; collected.boards = [UUID()]
        for c in [old, favorite, collected] { try vault.save(c) }
        let history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        history.retention = 1; await history.flush()
        XCTAssertEqual(Set(try vault.load().map(\.id)), Set([favorite.id, collected.id]))
    }
    func testMultiCopyFollowsVisibleOrderAndStackDeduplicates() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        history.stackRecording = true
        let a = makeClip("Premier"); let b = makeClip("Second"); history.add(a); history.add(b); history.add(makeClip("Premier")); await history.flush()
        XCTAssertEqual(history.stack, [a.id,b.id])
        history.trashItems([a,b]); await history.flush()
        XCTAssertEqual(try vault.load().filter { $0.trashedAt != nil }.count, 2)
        history.undoTrash(); await history.flush()
        XCTAssertTrue(try vault.load().allSatisfy { $0.trashedAt == nil })
        history.stack = [a.id,b.id]
        let result = ClipQuery(collection: "stack", stack: history.stack).apply(history.clips)
        XCTAssertEqual(result.map(\.text), ["Premier","Second"])
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let ok = await history.copy(result, to: pb)
        XCTAssertTrue(ok); XCTAssertEqual(pb.string(forType: .string), "Premier\nSecond")
    }
}
final class SearchTests: XCTestCase {
    func testSearchCombinesAccentsOCRTypesBoardsAndTrash() {
        var a = makeClip("Réponse à garder"); a.ocr = "Texte caché dans une image"; a.kind = .image
        let board = UUID(); a.boards = [board]
        let b = makeClip("Autre réponse"); var trash = a; trash.id = UUID(); trash.trashedAt = Date()
        XCTAssertEqual(ClipQuery(text: "reponse cache", collection: board.uuidString, kind: .image).apply([a,b,trash]).map(\.id), [a.id])
        XCTAssertEqual(ClipQuery(collection: "trash").apply([a,b,trash]).map(\.id), [trash.id])
        XCTAssertEqual(Clip.kind(for: "#FFF"), .color); XCTAssertEqual(Clip.kind(for: "1a2b3c"), .color)
        XCTAssertEqual(Clip.kind(for: "https://example.com"), .link); XCTAssertEqual(Clip.kind(for: "un lien https://example.com"), .text)
    }
    func testTenThousandItemsSearchPerformance() {
        let clips = (0..<10_000).map { i -> Clip in var c = makeClip("Note \(i) : organiser mes idées pour le projet et garder une réponse utile."); c.title = "Note \(i)"; return c.metadata() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = ClipQuery(text: "9999 projet").apply(clips)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start)*1000
        XCTAssertEqual(result.count, 1)
        print("EasyPaste benchmark: 10000 notes / 2 termes = \(String(format: "%.1f", elapsed)) ms")
        XCTAssertLessThan(elapsed, 1500, "Recherche excessivement lente")
    }
}
func makeClip(_ text: String) -> Clip {
    let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]])
    return Clip(title: text, text: text, source: "Test", sourceID: "test", kind: Clip.kind(for: text), fingerprint: Clip.fingerprint(payload), payload: payload)
}

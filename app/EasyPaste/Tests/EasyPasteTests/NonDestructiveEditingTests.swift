import XCTest
import AppKit
import CryptoKit
@testable import EasyPaste

@MainActor final class NonDestructiveEditingTests: XCTestCase {
    private var folder: URL!
    private var vault: ClipVault!
    private var history: History!
    private var suite: String!
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        suite = UUID().uuidString
        history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: suite)!)
    }
    override func tearDown() async throws {
        history.stopMonitoring(); await history.flush()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
    private func original(_ text: String) async throws -> Clip {
        var value = makeClip(text)
        value.sourceURL = "https://example.com/source"; value.boards = [UUID()]; value.pinned = true
        history.add(value); await history.flush()
        history.recordPaste([value]); await history.flush()
        return try await history.fullClip(value)
    }
    func testRichTextLinkAndColorEditsKeepEncryptedOriginalBytesAndCounts() async throws {
        for text in ["Texte initial", "https://example.com/link", "#AABBCC"] {
            let source = try await original(text)
            let file = folder.appendingPathComponent(source.id.uuidString + ".clip")
            let bytes = try Data(contentsOf: file)
            let rich = NSAttributedString(string: "Texte modifié", attributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
            let rtf = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            let saved = try await history.saveEditedText(rich.string, title: "Titre modifié", rtf: rtf, original: source)
            let full = try await history.fullClip(saved)
            XCTAssertNotEqual(saved.id, source.id); XCTAssertEqual(saved.parentID, source.id)
            XCTAssertEqual(full.sourceURL, source.sourceURL); XCTAssertEqual(full.boards, source.boards)
            XCTAssertFalse(full.pinned); XCTAssertEqual(full.text, rich.string)
            XCTAssertEqual(full.payload.representations[0].first { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }?.data, rtf)
            XCTAssertEqual(try Data(contentsOf: file), bytes, "Saving must never rewrite the source record")
            XCTAssertEqual(history.pasteUsage.count(for: source.id), 1)
            XCTAssertEqual(history.pasteUsage.count(for: saved.id), 0)
        }
    }
    func testAllStructuredFormatsSaveSeparateRecordsEvenWithIdenticalOutput() async throws {
        let fixtures: [(StructuredFormat, String)] = [(.json, "{\"a\":1}"), (.sql, "select 1;"), (.csv, "nom;ville\nÉlodie;Lyon"), (.xml, "<root><item/></root>"), (.markdown, "# Titre\n\nUn texte."), (.svg, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>")]
        for (format, text) in fixtures {
            let source = try await original(text), model = StructuredEditorModel(clip: source, format: format)
            let file = folder.appendingPathComponent(source.id.uuidString + ".clip"), bytes = try Data(contentsOf: file)
            model.refresh()
            for _ in 0..<500 { if !model.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(model.canUseOutput, "\(format)")
            let output = model.output, before = history.clips.count
            await model.save(history: history)
            let first = try XCTUnwrap(history.selectedClip)
            await model.save(history: history)
            let second = try XCTUnwrap(history.selectedClip)
            XCTAssertEqual(history.clips.count, before + 2)
            XCTAssertNotEqual(first.id, second.id); XCTAssertNotEqual(first.id, source.id)
            XCTAssertEqual(first.parentID, source.id); XCTAssertEqual(second.parentID, source.id)
            let persisted = try await history.fullClip(second); XCTAssertEqual(persisted.text, output)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            XCTAssertEqual(model.original.id, source.id)
            model.cancel()
        }
    }
    func testNewSnippetsNeverOverwriteMatchingHistory() async throws {
        let source = try await original("Même texte")
        let bytes = try Data(contentsOf: folder.appendingPathComponent(source.id.uuidString + ".clip"))
        let first = try await history.makeSnippet("Nouveau", text: source.text)
        let second = try await history.makeSnippet("Encore", text: source.text)
        XCTAssertEqual(Set([source.id, first.id, second.id]).count, 3)
        XCTAssertEqual(history.clips.count, 3)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(source.id.uuidString + ".clip")), bytes)
    }
    func testFailedSaveDoesNotPublishVariantOrAlterSource() async throws {
        let source = try await original("Original")
        let bytes = try Data(contentsOf: folder.appendingPathComponent(source.id.uuidString + ".clip"))
        history.stopMonitoring()
        do { _ = try await history.saveEditedText("Modifié", title: "Titre", rtf: nil, original: source); XCTFail("Must reject during shutdown") } catch { }
        XCTAssertEqual(history.clips.count, 1)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(source.id.uuidString + ".clip")), bytes)
    }
}

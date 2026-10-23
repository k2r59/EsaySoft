import AppKit
import CryptoKit
import XCTest
@testable import EasyPaste

@MainActor final class WebClipboardIntegrationTests: XCTestCase {
    func testSheetsValuesPasteRemovesFormulaMetadataButPreservesTSVAndRichOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-sheets-" + UUID().uuidString)
        let suite = "EasyPaste.test.sheets." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let history = History(vault: try ClipVault(directory: folder, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let source = NSPasteboard(name: .init(UUID().uuidString)), destination = NSPasteboard(name: .init(UUID().uuidString))
        defer { source.releaseGlobally(); destination.releaseGlobally() }
        let values = "Total\t42\t1 234,50 €\nNote\t\"Deux lignes\navec tabulation\tinterne\"\t"
        let html = "<google-sheets-html-origin><table><tr><td>Total</td><td data-sheets-formula=\"=SUM(A1:A3)\" style=\"font-weight:bold\">42</td><td>1 234,50 €</td></tr></table></google-sheets-html-origin>"
        let item = NSPasteboardItem()
        item.setString(values, forType: .string); item.setString(html, forType: .html)
        XCTAssertTrue(source.writeObjects([item]))
        let clip = try XCTUnwrap(ClipboardReader.read(source, source: "Google Chrome", sourceID: "com.google.Chrome", exclusions: []))
        history.add(clip); await history.flush()
        let saved = try XCTUnwrap(history.clips.first)
        let copied = await history.copy([saved], plain: true, to: destination)
        XCTAssertTrue(copied)
        XCTAssertEqual(destination.string(forType: .string), values)
        XCTAssertEqual(destination.pasteboardItems?.first?.types, [.string])
        let restored = await history.copy([saved], to: destination)
        XCTAssertTrue(restored)
        XCTAssertEqual(destination.string(forType: .html), html)
        XCTAssertEqual(destination.string(forType: .string), values)
        history.stopMonitoring()
    }
    func testCaptureAndAnnotationKeepOriginWithoutAddingItToPastedText() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-origin-" + UUID().uuidString)
        let suite = "EasyPaste.test.origin." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let history = History(vault: try ClipVault(directory: folder, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let url = "https://example.com/document"
        let text = try await history.saveOCR("Une capture de texte", sourceURL: url)
        XCTAssertEqual(text.sourceURL, url)
        let copied = await history.copy([text], to: pb)
        XCTAssertTrue(copied); XCTAssertEqual(pb.string(forType: .string), "Une capture de texte")
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let data = try CaptureImage.png(XCTUnwrap(context.makeImage()))
        let image = try await history.saveImage(data, sourceURL: url)
        let annotated = try await history.saveImage(data, parent: image)
        XCTAssertEqual(annotated.sourceURL, url)
        let saved = try await history.fullClip(annotated)
        XCTAssertEqual(saved.sourceURL, url); XCTAssertEqual(saved.imageData, data)
        history.stopMonitoring(); await history.flush()
    }
    func testHTMLAndPlainTextSurviveEncryptedHistoryAndRecopy() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-web-" + UUID().uuidString)
        let suite = "EasyPaste.test.web." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: defaults)
        let source = NSPasteboard(name: .init(UUID().uuidString))
        let destination = NSPasteboard(name: .init(UUID().uuidString))
        defer { source.releaseGlobally(); destination.releaseGlobally() }
        let text = "Article français\nUn texte riche : été, œuf et €\nNom\tValeur\nCyril\t42"
        let html = "<div style=\"background-color:rgb(255, 255, 255)\"><h1>Article français</h1><p>Un <strong>texte riche</strong> : été, œuf et €</p><table><tr><th>Nom</th><th>Valeur</th></tr><tr><td>Cyril</td><td>42</td></tr></table></div>"
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(html.utf8), forType: .html)
        item.setString("https://example.com/article", forType: BrowserOrigin.chromiumType)
        XCTAssertTrue(source.writeObjects([item]))
        let clip = try XCTUnwrap(ClipboardReader.read(source, source: "Google Chrome", sourceID: "com.google.Chrome", exclusions: []))
        XCTAssertEqual(clip.kind, .text)
        XCTAssertEqual(clip.text, text)
        history.add(clip)
        await history.flush()
        let metadata = try XCTUnwrap(history.clips.first)
        XCTAssertTrue(metadata.payload.representations.isEmpty, "History cards must not retain the HTML payload")
        let copied = await history.copy([metadata], to: destination)
        XCTAssertTrue(copied)
        XCTAssertEqual(destination.string(forType: .string), text)
        XCTAssertEqual(destination.data(forType: .html), Data(html.utf8), "Formatting bytes must survive storage unchanged")
        let plainCopied = await history.copy([metadata], plain: true, to: destination)
        XCTAssertTrue(plainCopied)
        XCTAssertEqual(destination.string(forType: .string), text)
        XCTAssertNil(destination.data(forType: .html), "Plain paste must strip the HTML representation")
        let saved = try await history.fullClip(metadata)
        XCTAssertEqual(saved.sourceURL, "https://example.com/article")
        XCTAssertEqual(saved.payload, clip.payload, "Plain paste must not alter the rich original")
        history.stopMonitoring()
    }
}

import AppKit
import CryptoKit
import XCTest
@testable import EasyPaste

final class ImageTextLayoutTests: XCTestCase {
    private func fragment(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 100, _ height: CGFloat = 12) -> RecognizedTextLayout.Fragment {
        .init(text: text, bounds: CGRect(x: x, y: y, width: width, height: height))
    }
    func testBadgeStaysBesideDateRegardlessOfObservationOrder() {
        let fragments = [fragment("Expedia", 152, 182, 42, 8), fragment("ALICE MARTIN", 20, 220),
                         fragment("ID : 120045", 20, 200), fragment("17 nov. 2026 · digipec", 20, 180, 124),
                         fragment("Card not debited", 20, 160, 110), fragment("Stripe card", 138, 162, 60, 8)]
        let expected = "ALICE MARTIN\nID : 120045\n17 nov. 2026 · digipec Expedia\nCard not debited Stripe card"
        XCTAssertEqual(RecognizedTextLayout.render(fragments), expected)
        XCTAssertEqual(RecognizedTextLayout.render(fragments.reversed()), expected)
    }
    func testKeepsBlankLineBetweenCardsAndNoBlankLinesInsideCards() {
        let cards = [fragment("ALICE MARTIN", 20, 240), fragment("ID : 120045", 20, 220), fragment("Expedia", 20, 200),
                     fragment("BRUNO DURAND", 20, 150), fragment("ID : 120046", 20, 130), fragment("Booking", 20, 110)]
        XCTAssertEqual(RecognizedTextLayout.render(cards), "ALICE MARTIN\nID : 120045\nExpedia\n\nBRUNO DURAND\nID : 120046\nBooking")
    }
    func testPreservesOrdinaryAndUniformDoubleSpacedLines() {
        for spacing in [CGFloat(18), CGFloat(30)] {
            let lines = (0..<5).map { fragment("Ligne \($0)", 20, 200 - CGFloat($0) * spacing) }
            XCTAssertEqual(RecognizedTextLayout.render(lines), (0..<5).map { "Ligne \($0)" }.joined(separator: "\n"))
        }
    }
    func testKeepsColumnsOnTheSameRowWithTextSeparators() {
        let cells = [fragment("Nom", 20, 200, 40), fragment("Total", 220, 200, 40),
                     fragment("Alice", 20, 180, 40), fragment("25,00 €", 220, 180, 50),
                     fragment("Bruno", 20, 160, 40), fragment("8,50 €", 220, 160, 50)]
        XCTAssertEqual(RecognizedTextLayout.render(cells), "Nom | Total\nAlice | 25,00 €\nBruno | 8,50 €")
    }
    func testAdjacentLinesAreNotMergedBySlightlyDifferentFontSizes() {
        let lines = [fragment("Titre", 20, 200, 100, 26), fragment("Sous-titre", 20, 177, 100, 16),
                     fragment("Texte", 20, 157, 100, 12)]
        XCTAssertEqual(RecognizedTextLayout.render(lines), "Titre\nSous-titre\nTexte")
    }
    func testListIndentationAndInternalWhitespaceArePreserved() {
        let lines = [fragment("Liste", 20, 200), fragment("• Premier élément", 38, 180),
                     fragment("  valeur  conservée  ", 20, 160)]
        XCTAssertEqual(RecognizedTextLayout.render(lines), "Liste\n   • Premier élément\nvaleur  conservée")
    }
    func testLargeEmptySpaceCreatesOneSeparatorNotHundredsOfEmptyLines() {
        XCTAssertEqual(RecognizedTextLayout.render([fragment("Haut", 0, 1000), fragment("Bas", 0, 0)]), "Haut\n\nBas")
    }
    func testEmptyInvalidAndExtremeGeometryAreBounded() {
        XCTAssertEqual(RecognizedTextLayout.render([]), "")
        XCTAssertEqual(RecognizedTextLayout.render([fragment(" \n ", 0, 0), fragment("invalid", 0, 0, 0)]), "")
        let output = RecognizedTextLayout.render([fragment("Début", 0, 20), fragment("Fin", 1e100, 0)])
        XCTAssertEqual(output, "Début\n" + String(repeating: " ", count: 24) + "Fin")
    }
    func testLayoutIsInvariantUnderImageScale() {
        let fragments = [fragment("Titre", 10, 200), fragment("Date", 10, 180, 60), fragment("Badge", 80, 182, 30, 8), fragment("Suite", 10, 100)]
        let scaled = fragments.map { RecognizedTextLayout.Fragment(text: $0.text, bounds: $0.bounds.applying(.init(scaleX: 2, y: 2))) }
        XCTAssertEqual(RecognizedTextLayout.render(fragments), RecognizedTextLayout.render(scaled))
    }
    func testThreeColumnsKeepVisualOrderDespiteShuffledObservations() {
        let cells = [fragment("Produit", 20, 200, 70), fragment("Quantité", 220, 200, 70), fragment("Prix", 420, 200, 50),
            fragment("Clavier", 20, 180, 60), fragment("USB", 85, 181, 25), fragment("2", 220, 180, 15), fragment("40 €", 420, 180, 50),
            fragment("Souris", 20, 160, 60), fragment("1", 220, 160, 15), fragment("15 €", 420, 160, 50)]
        let expected = "Produit | Quantité | Prix\nClavier USB | 2 | 40 €\nSouris | 1 | 15 €"
        XCTAssertEqual(RecognizedTextLayout.render(cells), expected)
        XCTAssertEqual(RecognizedTextLayout.render(cells.reversed()), expected)
        let columnMajor = cells.sorted { $0.bounds.minX < $1.bounds.minX }
        XCTAssertEqual(RecognizedTextLayout.render(columnMajor), expected)
    }
    func testRecognizedMarkupRemainsLiteralText() {
        let source = "<script>alert('x')</script> & <img src=\"https://example.invalid/pixel\">"
        XCTAssertEqual(RecognizedTextLayout.render([fragment(source, 0, 0, 500)]), source)
    }
    @MainActor func testRealTableImageIsCopiedInRowOrderAsPlainText() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 420, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 420))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let rows = [["Produit", "Stock", "Rayon"], ["Clavier", "12", "Bureau"], ["Souris", "18", "Atelier"]]
        for (row, cells) in rows.enumerated() {
            for (column, text) in cells.enumerated() {
                (text as NSString).draw(at: CGPoint(x: 40 + column * 400, y: 320 - row * 100),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try CaptureImage.png(XCTUnwrap(context.makeImage()))
        let recognized = try ImageText.recognize(png)
        XCTAssertEqual(recognized, rows.map { $0.joined(separator: " | ") }.joined(separator: "\n"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "EasyPaste.test.table." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let history = History(vault: try ClipVault(directory: folder, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        defer { history.stopMonitoring(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let clip = try await history.saveOCR(recognized)
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let copied = await history.copy([clip], to: pb)
        XCTAssertTrue(copied)
        XCTAssertEqual(pb.string(forType: .string), recognized)
        XCTAssertEqual(pb.pasteboardItems?.first?.types, [.string])
        await history.flush()
    }
    @MainActor func testRealVisionRestoresCardRowsAndSeparators() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 900, height: 850, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 900, height: 850))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 24) {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
        }
        for (index, name) in ["ALICE MARTIN", "BRUNO DURAND", "CLAIRE ROBERT"].enumerated() {
            let y = CGFloat(770 - index * 250)
            draw(name, x: 40, y: y, size: 28)
            draw("ID : 12004\(index)", x: 40, y: y - 38)
            draw("17 nov. 2026 - digipec", x: 40, y: y - 76)
            draw("Expedia", x: 310, y: y - 73, size: 18)
            draw("Card not debited", x: 40, y: y - 114)
            draw("Stripe card", x: 245, y: y - 111, size: 18)
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try CaptureImage.png(XCTUnwrap(context.makeImage()))
        let text = try ImageText.recognize(png)
        let blocks = text.components(separatedBy: "\n\n")
        XCTAssertEqual(blocks.count, 3, text)
        for (index, name) in ["ALICE MARTIN", "BRUNO DURAND", "CLAIRE ROBERT"].enumerated() {
            guard blocks.indices.contains(index) else { continue }
            let lines = blocks[index].components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 4, blocks[index])
            XCTAssertTrue(lines.first?.contains(name) == true, blocks[index])
            guard lines.count == 4 else { continue }
            XCTAssertTrue(lines[1].hasPrefix("ID"), "The ID must stay immediately below the name: \(blocks[index])")
            XCTAssertTrue(lines[2].contains("2026") && lines[2].contains("Expedia"), blocks[index])
            XCTAssertTrue(lines[3].contains("Card not debited") && lines[3].contains("Stripe card"), blocks[index])
            if let status = lines[3].range(of: "Card not debited"), let badge = lines[3].range(of: "Stripe card") {
                XCTAssertLessThan(status.lowerBound, badge.lowerBound)
            }
        }
    }
}

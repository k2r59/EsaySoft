import AppKit
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
    func testKeepsColumnsOnTheSameRowWithTabs() {
        let cells = [fragment("Nom", 20, 200, 40), fragment("Total", 220, 200, 40),
                     fragment("Alice", 20, 180, 40), fragment("25,00 €", 220, 180, 50),
                     fragment("Bruno", 20, 160, 40), fragment("8,50 €", 220, 160, 50)]
        XCTAssertEqual(RecognizedTextLayout.render(cells), "Nom\tTotal\nAlice\t25,00 €\nBruno\t8,50 €")
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
    func testHTMLKeepsSharedColumnsAndBlockSeparators() throws {
        let document = RecognizedTextLayout.document([fragment("Nom", 20, 200, 60), fragment("Total", 220, 200, 50),
            fragment("Alice", 20, 180, 60), fragment("25 €", 220, 180, 50), fragment("Suite", 20, 100, 60)])
        let html = try XCTUnwrap(document.html)
        XCTAssertEqual(document.text, "Nom\tTotal\nAlice\t25 €\n\nSuite")
        XCTAssertEqual(html.components(separatedBy: "<col width=").count - 1, 2)
        XCTAssertTrue(html.contains("colspan=\"2\""))
        XCTAssertTrue(html.contains("height:14px;line-height:14px"))
        XCTAssertLessThan(try XCTUnwrap(html.range(of: ">Nom<")).lowerBound, try XCTUnwrap(html.range(of: ">Total<")).lowerBound)
    }
    func testHTMLTreatsRecognizedMarkupAsTextWithoutActiveContent() throws {
        let source = "<script>alert('x')</script> & <img src=\"https://example.invalid/pixel\">"
        let document = RecognizedTextLayout.document([fragment(source, 0, 0, 500)])
        let html = try XCTUnwrap(document.html)
        XCTAssertEqual(document.text, source)
        XCTAssertFalse(html.contains("<script>")); XCTAssertFalse(html.contains("<img "))
        XCTAssertTrue(html.contains("&lt;script&gt;")); XCTAssertTrue(html.contains("&amp;")); XCTAssertTrue(html.contains("&quot;"))
    }
    func testPlainIndexingDoesNotBuildRichRepresentation() {
        let document = RecognizedTextLayout.document([fragment("Texte", 0, 0)], includeHTML: false)
        XCTAssertEqual(document.text, "Texte"); XCTAssertNil(document.html)
        XCTAssertTrue(RecognizedTextLayout.html(forText: "A\tB\n\n<x>").contains("A\tB\n\n&lt;x&gt;"))
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
        let document = try ImageText.recognizeDocument(png)
        let text = document.text
        // Exercise a real macOS rich-text importer, not just string matching.
        let html = try XCTUnwrap(document.html)
        let rich = try NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        for name in ["ALICE MARTIN", "BRUNO DURAND", "CLAIRE ROBERT"] { XCTAssertTrue(rich.string.contains(name), rich.string) }
        XCTAssertTrue(rich.string.contains("Expedia")); XCTAssertTrue(rich.string.contains("Stripe card"))
        let blocks = text.components(separatedBy: "\n\n")
        XCTAssertEqual(blocks.count, 3, text)
        for (index, name) in ["ALICE MARTIN", "BRUNO DURAND", "CLAIRE ROBERT"].enumerated() {
            guard blocks.indices.contains(index) else { continue }
            let lines = blocks[index].components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 4, blocks[index])
            XCTAssertTrue(lines.first?.contains(name) == true, blocks[index])
            XCTAssertTrue(lines.contains { $0.contains("2026") && $0.contains("Expedia") }, blocks[index])
            XCTAssertTrue(lines.contains { $0.contains("Card not debited") && $0.contains("Stripe card") }, blocks[index])
        }
    }
}

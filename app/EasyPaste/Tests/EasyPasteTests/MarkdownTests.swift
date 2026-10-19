import XCTest
import AppKit
@testable import EasyPaste

enum MarkdownFixtures {
    static let document = """
    # Notes de version

    Un aperçu **lisible**, *natif* et ~~sans détour~~. [Voir le projet](https://github.com/k2r59/EsaySoft).

    ## À retenir
    - Titres et listes
    - [x] Recherche intégrée
    - [ ] Prochaine idée

    > Le Markdown reste intact lors de la copie.

    ```swift
    let message = "Bonjour, Élodie !"
    ```

    | Format | Vue |
    | :--- | :--- |
    | Markdown | Aperçu |
    | CSV | Tableau |
    """
}

final class MarkdownTests: XCTestCase {
    func testSourceRemainsByteForByteUnchanged() throws {
        let source = "\u{FEFF}# Titre\r\n\r\n**Texte**  \r\nsuite\r\n"
        let result = try StructuredText.process(source, format: .markdown, presentation: .rendered)
        XCTAssertEqual(Array(result.text.utf8), Array(source.utf8)); XCTAssertNotNil(result.markdown)
        XCTAssertEqual(StructuredFormat.markdown.fileExtension, "md")
    }
    func testHeadingsInlineStylesAndParagraphBoundaries() throws {
        let doc = try MarkdownDocument.parse("# Titre\n\nUn **mot** *italique* ~~barré~~ et `code`.\n\n## Suite")
        XCTAssertEqual(doc.text, "Titre\nUn mot italique barré et code.\nSuite")
        XCTAssertEqual(doc.blocks.map(\.heading), [1,0,2])
        let text = doc.text as NSString
        XCTAssertEqual(doc.spans.filter(\.bold).map { text.substring(with: $0.range) }, ["mot"])
        XCTAssertEqual(doc.spans.filter(\.italic).map { text.substring(with: $0.range) }, ["italique"])
        XCTAssertEqual(doc.spans.filter(\.strike).map { text.substring(with: $0.range) }, ["barré"])
        XCTAssertEqual(doc.spans.filter(\.code).map { text.substring(with: $0.range) }, ["code"])
    }
    func testNestedListsQuotesAndTaskLists() throws {
        let doc = try MarkdownDocument.parse("3. Trois\n4. Quatre\n   - enfant\n\n- [x] Fait\n- [ ] À faire\n\n> Citation\n>\n> > Suite")
        XCTAssertTrue(doc.text.contains("3.\tTrois")); XCTAssertTrue(doc.text.contains("4.\tQuatre"))
        XCTAssertTrue(doc.text.contains("•\tenfant")); XCTAssertTrue(doc.blocks.contains { $0.listDepth == 2 })
        XCTAssertTrue(doc.text.contains("☑\tFait")); XCTAssertTrue(doc.text.contains("☐\tÀ faire"))
        XCTAssertTrue(doc.blocks.contains { $0.quoteDepth == 2 })
    }
    func testListContinuationDoesNotRepeatBullet() throws {
        let doc = try MarkdownDocument.parse("- premier\n\n  suite du même élément\n\n- second")
        XCTAssertEqual(doc.text.filter { $0 == "•" }.count, 2)
        XCTAssertTrue(doc.text.contains("suite du même élément"))
    }
    func testCodeBlocksNeverInterpretTheirContents() throws {
        let doc = try MarkdownDocument.parse("```html\n<script>alert(1)</script>\n**pas en gras**\n```\n\n    code indenté")
        XCTAssertTrue(doc.text.contains("<script>alert(1)</script>\n**pas en gras**"))
        XCTAssertTrue(doc.blocks.allSatisfy(\.code)); XCTAssertFalse(doc.spans.contains(where: \.bold))
    }
    func testTablesKeepCellCoordinatesAndAlignment() throws {
        let doc = try MarkdownDocument.parse("| Nom | Valeur |\n| :--- | ---: |\n| **Élodie** | 00123 |\n| B | 3 |")
        let cells = doc.blocks.compactMap(\.cell)
        XCTAssertEqual(cells.count, 6); XCTAssertEqual(cells.map(\.row), [0,0,1,1,2,2])
        XCTAssertEqual(cells.map(\.column), [0,1,0,1,0,1]); XCTAssertTrue(cells[1].alignment == .right)
        XCTAssertTrue(cells.prefix(2).allSatisfy(\.header)); XCTAssertTrue(doc.text.contains("00123"))
    }
    func testEscapesEntitiesHardBreaksAndUnicode() throws {
        let doc = try MarkdownDocument.parse("\\*littéral\\* &amp; é😀  \nligne\n\nTitre\n=====")
        XCTAssertEqual(doc.text, "*littéral* & é😀\nligne\nTitre"); XCTAssertEqual(doc.blocks.last?.heading, 1)
        for span in doc.spans { XCTAssertLessThanOrEqual(NSMaxRange(span.range), (doc.text as NSString).length) }
    }
    func testUnfinishedMarkdownRemainsReadableAndCopyable() throws {
        for source in ["", "#", "**gras inachevé", "[lien](", "![image](", "```swift\nlet x = 1", "| a | b |\n| -- |\n| 1", "> > >", "<script>alert(1)</script>", "\u{0000}é😀"] {
            let result = try StructuredText.process(source, format: .markdown)
            XCTAssertEqual(result.text, source); XCTAssertNotNil(result.markdown)
        }
        XCTAssertTrue(try MarkdownDocument.parse("**inachevé").text.contains("**inachevé"))
    }
    func testLinksAndImagesNeverBecomeExecutableContent() throws {
        let doc = try MarkdownDocument.parse("[web](https://example.com) [mail](mailto:test@example.com) [script](javascript:alert(1)) [file](file:///etc/passwd) [data](data:text/html,test) [local](/tmp/x) ![logo](https://example.com/logo.png)")
        XCTAssertEqual(doc.spans.compactMap(\.link).map { $0.scheme! }, ["https", "mailto"])
        XCTAssertTrue(doc.hasImages); XCTAssertTrue(doc.text.contains("Image : logo"))
        XCTAssertFalse(MarkdownDocument.allowedLink(URL(string: "easypaste:delete")!))
    }
    func testAutomaticDetectionKeepsOtherFormats() {
        for source in ["# Titre", "Titre\n====", "- un\n- deux", "**important**", "[Lien](https://example.com)", "```json\n{}\n```", "| A | B |\n| --- | --- |\n| a | b |"] {
            XCTAssertEqual(StructuredText.hint(source), .markdown, source)
        }
        for source in ["Une phrase ordinaire", "a * b", "#12345", "un, deux, trois"] { XCTAssertNil(StructuredText.hint(source), source) }
        XCTAssertEqual(StructuredText.hint(#"{"message":"**gras**"}"#), .json)
        XCTAssertEqual(StructuredText.hint(#"["**gras**"]"#), .json)
        XCTAssertEqual(StructuredText.hint("<p>**gras**</p>"), .xml)
        XCTAssertEqual(StructuredText.hint("select '**gras**' from clients"), .sql)
        XCTAssertEqual(StructuredText.hint("id;nom\n00123;Cyril"), .csv)
    }
    func testPreviewBudgetsAndUTF8Boundary() throws {
        let source = String(repeating: "é😀", count: 100_000)
        let result = try StructuredText.process(source, format: .markdown)
        XCTAssertEqual(result.text, source); XCTAssertTrue(result.markdown!.truncated)
        XCTAssertFalse(result.markdown!.text.contains("�"))
        let blocks = try MarkdownDocument.parse(String(repeating: "# h\n\n", count: 3000))
        XCTAssertTrue(blocks.truncated); XCTAssertLessThanOrEqual(blocks.blocks.count, MarkdownDocument.blockLimit)
        let spans = try MarkdownDocument.parse(String(repeating: "**b** *i* ", count: 3000))
        XCTAssertTrue(spans.truncated); XCTAssertLessThanOrEqual(spans.spans.count, MarkdownDocument.spanLimit)
        XCTAssertThrowsError(try StructuredText.process(String(repeating: "a", count: StructuredText.inputLimit + 1), format: .markdown))
    }
    func testWideTablesAndEmptyImageLabelsAreBounded() throws {
        let source = Array(repeating: "h", count: 500).joined(separator: "|") + "\n" + Array(repeating: "---", count: 500).joined(separator: "|") + "\n" + Array(repeating: "v", count: 500).joined(separator: "|")
        let result = try StructuredText.process(source, format: .markdown)
        XCTAssertEqual(result.text, source); XCTAssertTrue(result.markdown!.truncated)
        XCTAssertTrue(result.markdown!.blocks.compactMap(\.cell).allSatisfy { $0.columns <= MarkdownDocument.columnLimit && $0.column < MarkdownDocument.columnLimit })
        XCTAssertEqual(try MarkdownDocument.parse("![](https://example.com/test.png)").text, "Image : sans description")
    }
    func testMalformedMutationCorpusNeverChangesSource() throws {
        let seeds = [MarkdownFixtures.document, "[lien](https://example.com \"titre\")\n\n![alt](image.png)", "***gras***\n\n> - [x] test\n\n````\ncode\n````"]
        var count = 0
        for seed in seeds {
            let chars = Array(seed)
            for index in chars.indices {
                var removed = chars; removed.remove(at: index)
                for input in [String(chars.prefix(index)), String(removed)] {
                    let result = try StructuredText.process(input, format: .markdown)
                    XCTAssertEqual(result.text, input)
                    let doc = try XCTUnwrap(result.markdown)
                    XCTAssertTrue(doc.spans.allSatisfy { NSMaxRange($0.range) <= (doc.text as NSString).length })
                    count += 1
                }
            }
        }
        print("MARKDOWN_MUTATIONS \(count)")
    }
    func testCancellationIsRespected() async throws {
        let task = Task.detached { () throws -> MarkdownDocument in
            while !Task.isCancelled { try Task.checkCancellation(); await Task.yield() }
            return try MarkdownDocument.parse(MarkdownFixtures.document)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled parse must not publish a result") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
    func testAdversarialInputsStayBounded() throws {
        let start = Date()
        for input in [String(repeating: "[", count: 100_000), String(repeating: "*a", count: 50_000), String(repeating: "> ", count: 20_000) + "nested", String(repeating: "`", count: 100_000)] {
            let doc = try MarkdownDocument.parse(input)
            XCTAssertLessThanOrEqual(doc.blocks.count, MarkdownDocument.blockLimit)
            XCTAssertLessThanOrEqual(doc.spans.count, MarkdownDocument.spanLimit)
        }
        print("MARKDOWN_ADVERSARIAL \(Date().timeIntervalSince(start))s")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
    @MainActor func testNativeAttributesRenderHeadingsStylesAndTables() throws {
        let doc = try MarkdownDocument.parse(MarkdownFixtures.document), rendered = doc.attributed()
        XCTAssertEqual(rendered.string, doc.text)
        let heading = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(heading.pointSize, 28)
        let cell = try XCTUnwrap(doc.blocks.first { $0.cell != nil })
        let paragraph = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: cell.range.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertTrue(paragraph.textBlocks.first is NSTextTableBlock)
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in XCTAssertNil(value) }
    }
    @MainActor func testNativeLargePreviewStylingAndLayoutBudget() async throws {
        for source in [String(repeating: "## Section\n\nUn **mot** *italique* et `code`.\n\n", count: 1000), "| A | B |\n| --- | --- |\n" + String(repeating: "| cellule | **donnée** |\n", count: 1000)] {
            let document = try await Task.detached { try MarkdownDocument.parse(source) }.value
            let start = Date(), content = document.attributed(), styleTime = Date().timeIntervalSince(start)
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
            view.layoutManager?.allowsNonContiguousLayout = true
            view.textContainer?.widthTracksTextView = true; view.isHorizontallyResizable = false
            view.textStorage?.setAttributedString(content)
            let layoutStart = Date()
            view.layoutManager?.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: 640, height: 400), in: view.textContainer!)
            let layoutTime = Date().timeIntervalSince(layoutStart)
            print("MARKDOWN_NATIVE blocks=\(document.blocks.count) spans=\(document.spans.count) style=\(styleTime)s layout=\(layoutTime)s")
            XCTAssertLessThan(styleTime, 0.25); XCTAssertLessThan(layoutTime, 0.25)
        }
    }
}

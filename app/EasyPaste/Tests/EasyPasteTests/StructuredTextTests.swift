import XCTest
import AppKit
import CryptoKit
@testable import EasyPaste

final class StructuredTextTests: XCTestCase {
    func testJSONGoldenFormattingAndCompaction() throws {
        let input = #"{"id":900719925474099312345,"n":1.2300e+09,"z":-0,"s":"é😀\u00E9\/","id":2,"v":[true,null,{},[]]}"#
        let pretty = try StructuredText.process(input, format: .json).text
        XCTAssertTrue(pretty.contains("\n  \"id\": 900719925474099312345,"))
        XCTAssertTrue(pretty.contains("1.2300e+09")); XCTAssertTrue(pretty.contains("\"z\": -0"))
        XCTAssertEqual(try StructuredText.process(pretty, format: .json, presentation: .compact).text, input)
        XCTAssertEqual(try StructuredText.process(pretty, format: .json).text, pretty)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(pretty.utf8)) as? NSDictionary, try JSONSerialization.jsonObject(with: Data(input.utf8)) as? NSDictionary)
    }
    func testJSONRejectsMalformedSyntaxWithLocation() {
        for input in ["", "{", "[1,]", "{\"a\":1,}", "{a:1}", "01", "1.", "1e+", "NaN", "true false", "\"bad\ntext\"", #""\q""#, #""\u12xx""#, "{\n\"a\":1\n\"b\":2}"] {
            XCTAssertThrowsError(try StructuredText.process(input, format: .json), input) { error in
                XCTAssertNotNil((error as? TextIssue)?.line); XCTAssertNotNil((error as? TextIssue)?.column)
            }
        }
    }
    func testJSONScalarsAndUnicodeEscapes() throws {
        for input in ["true", "false", "null", "-123.45E-10", #""a\"b\\c\n\t\uD83D\uDE00""#, "[]", "{}"] {
            XCTAssertEqual(try StructuredText.process(" \n" + input + "\t", format: .json, presentation: .compact).text, input)
        }
        XCTAssertEqual(try StructuredText.process("\u{FEFF}{}", format: .json).text, "{}")
    }
    func testJSONDepthInputAndExpansionLimits() throws {
        XCTAssertThrowsError(try StructuredText.process(String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130), format: .json))
        XCTAssertThrowsError(try StructuredText.process(String(repeating: " ", count: StructuredText.inputLimit + 1), format: .json))
        let expansive = String(repeating: "[", count: 100) + Array(repeating: "0", count: 45_000).joined(separator: ",") + String(repeating: "]", count: 100)
        XCTAssertThrowsError(try StructuredText.process(expansive, format: .json))
        XCTAssertEqual(try StructuredText.process(expansive, format: .json, presentation: .compact).text, expansive)
    }
    func testJSONGeneratedRoundtrips() throws {
        for index in 0..<150 {
            let object: [String: Any] = ["id": index, "text": "é\n\"\\😀 \(index)", "items": [index, index + 1], "nested": ["flag": index % 2 == 0]]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let input = String(decoding: data, as: UTF8.self)
            let pretty = try StructuredText.process(input, format: .json).text
            XCTAssertEqual(try StructuredText.process(pretty, format: .json, presentation: .compact).text, input)
        }
    }
    func testCSVDetectsDelimitersAndPreservesValues() throws {
        for separator in [",", ";", "\t", "|"] {
            let input = "id\(separator)montant\(separator)texte\r\n00123\(separator)1.2300\(separator)\"bonjour\r\n\"\"Élodie\"\"\"\r\n"
            let csv = try CSVDocument.parse(input, delimiter: nil)
            XCTAssertEqual(csv.columnCount, 3); XCTAssertEqual(csv.rows.count, 2)
            XCTAssertEqual(csv.rows[1], ["00123", "1.2300", "bonjour\r\n\"Élodie\""])
            XCTAssertEqual(try CSVDocument.parse(csv.serialized(), delimiter: csv.delimiter).rows, csv.rows)
            XCTAssertEqual(csv.newline, "\r\n"); XCTAssertTrue(csv.trailingNewline)
        }
    }
    func testCSVEmptyCellsBOMAndWhitespaceArePreserved() throws {
        let input = "\u{FEFF}id,texte,vide\n001,  espace  ,\n002,\"\",\"\""
        let csv = try CSVDocument.parse(input, delimiter: nil)
        XCTAssertEqual(csv.rows[1], ["001", "  espace  ", ""])
        XCTAssertEqual(csv.rows[2], ["002", "", ""]); XCTAssertTrue(csv.bom); XCTAssertFalse(csv.trailingNewline)
        XCTAssertTrue(try csv.serialized().hasPrefix("\u{FEFF}"))
        XCTAssertEqual(try CSVDocument.parse(csv.serialized(), delimiter: 44).rows, csv.rows)
    }
    func testCSVInvalidQuotingAndRaggedRowsFailClearly() {
        for input in ["a,b\n\"oops,b", "a,b\n1,2,3", "a,b\n\"x\"oops,2", "a,b\nfoo\"bar,2"] {
            XCTAssertThrowsError(try CSVDocument.parse(input, delimiter: 44), input)
        }
        XCTAssertThrowsError(try CSVDocument.parse(Array(repeating: "x", count: 257).joined(separator: ","), delimiter: 44))
        XCTAssertThrowsError(try CSVDocument.parse("a;b\n1;\"oops", delimiter: nil)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Guillemet de fermeture"))
        }
    }
    func testCSVEditedCellEscapesOnlyAsRequired() throws {
        var csv = try CSVDocument.parse("id;valeur\n00123;avant", delimiter: nil)
        csv.rows[1][1] = "après;\"oui\"\n😀"
        XCTAssertEqual(try csv.serialized(), "id;valeur\n00123;\"après;\"\"oui\"\"\n😀\"")
        XCTAssertEqual(try CSVDocument.parse(csv.serialized(), delimiter: 59).rows, csv.rows)
    }
    func testXMLPrettyPrintAndIdempotence() throws {
        let input = #"<?xml version="1.0"?><racine xmlns:x="urn:test"><x:item id="001"><nom>Élodie &amp; Cyril</nom><vide/></x:item></racine>"#
        let value = try StructuredText.process(input, format: .xml)
        XCTAssertTrue(value.text.contains("\n  <x:item id=\"001\">\n    <nom>"))
        XCTAssertTrue(value.text.contains("Élodie &amp; Cyril")); XCTAssertEqual(value.xml.first?.children.first?.label, "<x:item>")
        XCTAssertEqual(try StructuredText.process(value.text, format: .xml).text, value.text)
    }
    func testXMLMixedTextCDATAAndSpaceAreBytePreserved() throws {
        for input in [#"<p>Bonjour <b>tout <i>le</i> monde</b> !</p>"#, #"<r xml:space="preserve"><a><b/></a> </r>"#, "<r> <a/>\t<b/>\n</r>", #"<r><![CDATA[<x> &  a  ]]><v/></r>"#] {
            XCTAssertEqual(try StructuredText.process(input, format: .xml).text, input)
        }
    }
    func testXMLCommentsPIAttributesAndCDATAAreOpaque() throws {
        let input = #"<root a="a &gt; b"><!-- <x> --><![CDATA[<tag>]]><?job a?><v/></root>"#
        XCTAssertEqual(try StructuredText.process(input, format: .xml).text, input)
        XCTAssertNoThrow(try StructuredText.process(#"<r><!-- <!DOCTYPE not-real> --><a/></r>"#, format: .xml))
    }
    func testXMLRejectsInvalidDTDAndExcessiveDepth() {
        for input in ["<r><a></r>", "<r a='1' a='2'/>", "<r>&unknown;</r>", "<r/><r/>", "<r>", #"<!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><r>&x;</r>"#, String(repeating: "<r>", count: 130) + String(repeating: "</r>", count: 130)] {
            XCTAssertThrowsError(try StructuredText.process(input, format: .xml), input)
        }
    }
    func testSQLClausesAndIdentifiersRemainIntact() throws {
        let input = "select identifiant, \"order\" from clients where id = 00123 order by identifiant limit 10;"
        let output = try SQLTextFormatter.format(input, dialect: .standard)
        XCTAssertTrue(output.contains("\nfrom clients\nwhere")); XCTAssertTrue(output.contains("\"order\"")); XCTAssertTrue(output.contains("00123"))
        XCTAssertEqual(try SQLTextFormatter.format(output, dialect: .standard), output)
        try assertSameSQLTokens(input, output, dialect: .standard)
    }
    func testSQLQuotedCommentsAndDialects() throws {
        let examples: [(SQLDialect, String)] = [
            (.postgres, "select $body$ from 'x' where $body$, E'a\\'b', 'x'\n'y' from t where x = $1;"),
            (.mysql, "select `from`, 'a\\'b' from `table` # where fake\nwhere x = 1;"),
            (.tsql, "SELECT [some]]name], N'a''b' FROM [dbo].[x] WHERE id = @id;"),
            (.sqlite, "select 'from where', `table` from tbl where x = ?1;"),
            (.standard, "/* start /* nested */ end */ select a /* WHERE x */ from t -- WHERE hidden\nwhere a = 'it''s fine';"),
            (.standard, "with data as (select x from y where z=1) select * from data;")
        ]
        for (dialect, input) in examples { let output = try SQLTextFormatter.format(input, dialect: dialect); try assertSameSQLTokens(input, output, dialect: dialect) }
    }
    private func assertSameSQLTokens(_ a: String, _ b: String, dialect: SQLDialect) throws {
        func values(_ s: String) throws -> [String] { let bytes = Array(s.utf8); return try SQLTextFormatter.lex(s, dialect: dialect).map { String(decoding: bytes[$0.range], as: UTF8.self) } }
        XCTAssertEqual(try values(a), try values(b))
    }
    func testSQLRejectsUnclosedTokens() {
        for input in ["select 'oops from t", "select (a from t", "select a) from t", "select /* oops", "select $$oops"] {
            XCTAssertThrowsError(try SQLTextFormatter.format(input, dialect: .standard), input)
        }
    }
    func testDetectionIsBoundedAndDoesNotStealOrdinaryText() {
        for input in ["Bonjour, Cyril", "123", "true", "https://example.com", "Je sélectionne une couleur", "#AABBCC"] { XCTAssertNil(StructuredText.hint(input), input) }
        XCTAssertEqual(StructuredText.hint("{\"a\":1}"), .json)
        XCTAssertEqual(StructuredText.hint("select * from clients"), .sql)
        XCTAssertEqual(StructuredText.hint("<racine/>"), .xml)
        XCTAssertEqual(StructuredText.hint("a;b\n1;2"), .csv)
        XCTAssertEqual(StructuredText.hint("a,b\n1,2\n"), .csv)
        XCTAssertEqual(StructuredText.hint("\u{FEFF}{\"id\":1}"), .json)
        XCTAssertEqual(StructuredText.hint("a,b\r1,2\r"), .csv)
        XCTAssertEqual(StructuredText.hint("<!-- note --><r/>"), .xml)
        XCTAssertNil(StructuredText.hint(String(repeating: "a", count: 1_000_000)))
    }
    func testUTF8PreviewNeverIntroducesReplacementCharacters() {
        for limit in 1..<32 {
            let prefix = StructuredText.prefix("é😀aé😀aé😀a", bytes: limit)
            XCTAssertFalse(prefix.contains("�")); XCTAssertLessThanOrEqual(prefix.utf8.count, limit)
        }
    }
    func testCancellationStopsEveryEngine() async {
        for (format, input) in [(StructuredFormat.json, "[1,2]"), (.csv, "a,b\n1,2"), (.xml, "<r/>"), (.sql, "select * from t")] {
            let started = expectation(description: "\(format) job started")
            let task = Task.detached {
                started.fulfill()
                for _ in 0..<100_000 { _ = try StructuredText.process(input, format: format) }
            }
            await fulfillment(of: [started], timeout: 2)
            task.cancel()
            do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        }
    }
    func testCSVGeneratedRoundtripsPreserveEveryCell() throws {
        let cases = ["", "00123", "a,b;c|d", "x\ny", "x\r\ny", "\"quoted\"", "é😀", "  ", "=SUM(A1)"]
        for delimiter: UInt8 in [44,59,9,124] {
            let rows = (0..<100).map { index in (0..<8).map { cases[(index * 3 + $0) % cases.count] } }
            let csv = CSVDocument(rows: rows, delimiter: delimiter, newline: "\r\n", trailingNewline: true, bom: false)
            XCTAssertEqual(try CSVDocument.parse(csv.serialized(), delimiter: delimiter).rows, rows)
        }
    }
    func testSQLNewlineSensitiveLiteralsStayAdjacentExactly() throws {
        let input = "select 'première'\n  'seconde', E'escape\\n' from test where nom = 'A';"
        let output = try SQLTextFormatter.format(input, dialect: .postgres)
        XCTAssertTrue(output.contains("'première'\n  'seconde'"))
        XCTAssertTrue(output.contains("E'escape\\n'"))
    }
    func testPreviewCacheInvalidatesWhenPayloadChanges() async throws {
        let first = try await StructuredPreviewCache.shared.preview(text: "{\"a\":1}", key: "format-cache-test-1", format: .json)
        let second = try await StructuredPreviewCache.shared.preview(text: "{\"a\":2}", key: "format-cache-test-2", format: .json)
        XCTAssertNotEqual(first, second)
        let cached = try await StructuredPreviewCache.shared.preview(text: "unused", key: "format-cache-test-1", format: .json)
        XCTAssertEqual(cached, first)
    }
    func testHintCacheCostWithLargeHistory() {
        let clips = (0..<10_000).map { makeClip("{\"id\":\($0)}") }
        let start = Date()
        for clip in clips { XCTAssertEqual(clip.structuredFormat, .json) }
        let elapsed = Date().timeIntervalSince(start)
        print("STRUCTURED_HINTS 10000 \(elapsed)s")
        XCTAssertLessThan(elapsed, 1)
    }
    func testMalformedMutationCorpusNeverCrashesOrGrowsWithoutBound() throws {
        let seeds: [(StructuredFormat, String)] = [(.json, #"{"a":[1,true,"é😀"],"b":{"n":null}}"#), (.csv, "id;nom\n001;\"Cyril\"\n002;Élodie"), (.sql, "select 'a''b', id from t where id in (1,2);"), (.xml, "<root a='1'><name>é &amp; 😀</name><empty/></root>")]
        let start = Date()
        var examined = 0, rejected = 0
        for (format, seed) in seeds {
            let characters = Array(seed)
            for index in characters.indices {
                var mutations: [String] = []
                var deleted = characters; deleted.remove(at: index); mutations.append(String(deleted))
                mutations.append(String(characters.prefix(index)))
                var changed = characters; changed[index] = "\""; mutations.append(String(changed))
                for input in mutations {
                    examined += 1
                    do {
                        let result = try StructuredText.process(input, format: format)
                        XCTAssertLessThan(result.text.utf8.count, 20_000)
                        XCTAssertNoThrow(try StructuredText.process(result.text, format: format), "A successfully formatted document must remain parseable: \(format)")
                    } catch { rejected += 1; XCTAssertTrue(error is TextIssue || error is CancellationError) }
                }
            }
        }
        print("STRUCTURED_MALFORMED_CORPUS \(examined) mutations, \(rejected) rejected, \(Date().timeIntervalSince(start))s")
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testLargeDocumentsHaveBoundedRuntime() throws {
        let json = "[" + Array(repeating: #"{"id":9007199254740993123,"text":"Élodie😀"}"#, count: 12_000).joined(separator: ",") + "]"
        let csv = "id;nom\n" + (0..<20_000).map { "\($0);Nom \($0)" }.joined(separator: "\n")
        let xml = "<r>" + String(repeating: "<item id='001'><name>Cyril</name></item>", count: 6000) + "</r>"
        for (format, input) in [(StructuredFormat.json, json), (.csv, csv), (.xml, xml)] {
            let start = Date(); _ = try StructuredText.process(input, format: format)
            let elapsed = Date().timeIntervalSince(start)
            print("STRUCTURED_BENCH \(format.rawValue) \(input.utf8.count) bytes \(elapsed)s")
            XCTAssertLessThan(elapsed, 4.0, "A bounded local job should not take seconds on these fixtures")
        }
    }
}

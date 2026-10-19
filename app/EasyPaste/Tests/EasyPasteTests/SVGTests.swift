import XCTest
import AppKit
@testable import EasyPaste

enum SVGFixtures {
    static let icon = "<svg xmlns='http://www.w3.org/2000/svg' width='120' height='80' viewBox='0 0 120 80'><rect x='5' y='5' width='110' height='70' rx='16' fill='#9BF1CB'/><path d='M30 40 L50 60 L90 20' fill='none' stroke='#172026' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
    static let gradient = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><defs><linearGradient id='paint'><stop offset='0%' stop-color='#9BF1CB'/><stop offset='100%' stop-color='#B3A1ED'/></linearGradient></defs><circle cx='50' cy='50' r='45' fill='url(#paint)'/></svg>"
}
final class SVGTests: XCTestCase {
    func testAllowedStaticSVGAndCanonicalRoundtrip() throws {
        for source in [SVGFixtures.icon, SVGFixtures.gradient, "<svg viewBox='0 0 20 10'><g transform='translate(1 2)'><rect width='5' height='5' style='fill: #abc; stroke: rgb(0, 0, 0); stroke-width: 1'/></g></svg>"] {
            let value = try SVGDocument.parse(source)
            XCTAssertTrue(value.canonical.hasPrefix("<svg xmlns=")); XCTAssertEqual(try SVGDocument.parse(value.canonical).canonical, value.canonical)
            XCTAssertEqual(StructuredText.hint(source), .svg)
        }
    }
    func testDimensionsNamespacesAndEscaping() throws {
        let value = try SVGDocument.parse("<v:svg xmlns:v='http://www.w3.org/2000/svg' width='80px' height='40px'><v:text x='2' y='20'>A &amp; B &lt;script&gt;</v:text></v:svg>")
        XCTAssertEqual(value.width, 80); XCTAssertEqual(value.height, 40)
        XCTAssertTrue(value.canonical.contains("A &amp; B &lt;script&gt;")); XCTAssertFalse(value.canonical.contains("<script>"))
        XCTAssertEqual(try SVGDocument.parse("<svg viewBox='0 0 60 20'/>").width, 60)
    }
    func testRejectsScriptsEventsForeignObjectsAndAnimations() {
        let bodies = ["<script>alert(1)</script>", "<foreignObject><p>HTML</p></foreignObject>", "<animate attributeName='href' to='javascript:alert(1)'/>", "<set attributeName='fill' to='red'/>", "<image href='https://example.com/track'/>", "<use href='#a'/>", "<style>@import url(https://example.com/a.css)</style>", "<a href='javascript:alert(1)'><rect/></a>", "<filter><feImage href='file:///etc/passwd'/></filter>"]
        for body in bodies { XCTAssertThrowsError(try SVGDocument.parse("<svg>\(body)</svg>"), body) }
        for attribute in ["onload='alert(1)'", "onclick='alert(1)'", "OnLoad='alert(1)'", "xml:base='https://example.com/'", "href='javascript:alert(1)'", "style='background: url(https://example.com)'", "style='fill: url(data:image/svg+xml,bad)'", "style='fill: u\\72l(https://example.com)'", "fill='url(https://example.com)'", "fill='url(&#106;avascript:alert(1))'"] {
            XCTAssertThrowsError(try SVGDocument.parse("<svg><rect \(attribute)/></svg>"), attribute)
        }
    }
    func testRejectsDTDXXEStylesheetsAndNamespaceConfusion() {
        for source in ["<!DOCTYPE svg [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><svg><text>&x;</text></svg>", "<!DOCTYPE svg SYSTEM 'https://example.com/test.dtd'><svg/>", "<?xml-stylesheet href='file:///tmp/style.css'?><svg/>", "<svg xmlns='http://www.w3.org/1999/xhtml'/>", "<svg><script xmlns='http://www.w3.org/2000/svg'/></svg>", "<svg xmlns:x='http://www.w3.org/1999/xlink'><rect x:href='https://example.com'/></svg>"] {
            XCTAssertThrowsError(try SVGDocument.parse(source), source)
        }
        XCTAssertEqual(StructuredText.hint("<!DOCTYPE svg><svg/>"), .svg)
    }
    func testReferenceGraphRejectsCyclesAndInvalidTargets() {
        for source in ["<svg><rect fill='url(#missing)'/></svg>", "<svg><g id='a'/><rect fill='url(#a)'/></svg>", "<svg><defs><clipPath id='a'><rect clip-path='url(#b)'/></clipPath><clipPath id='b'><rect clip-path='url(#a)'/></clipPath></defs></svg>", "<svg><g id='x'/><g id='x'/></svg>"] { XCTAssertThrowsError(try SVGDocument.parse(source)) }
    }
    func testMalformedNumbersXMLAndComplexityBudgets() {
        for source in ["", "<svg>", "<svg><g></svg>", "<svg width='0'/>", "<svg width='-1'/>", "<svg width='1e999'/>", "<svg viewBox='0 0 0 10'/>", "<svg><path d='M0 0 L1e999 2'/></svg>", "<svg><rect fill='#12345'/></svg>", "<svg><g transform='translate(1e999 2)'/></svg>", "<svg>" + String(repeating: "<g>", count: 33) + String(repeating: "</g>", count: 33) + "</svg>", "<svg>" + String(repeating: "<rect/>", count: 2001) + "</svg>", String(repeating: " ", count: SVGDocument.inputLimit + 1)] { XCTAssertThrowsError(try SVGDocument.parse(source)) }
    }
    func testXMLCommentsCDATAAndEscapedTextAreInert() throws {
        let doc = try SVGDocument.parse("<svg><!-- <script>alert(1)</script> --><text><![CDATA[<script>test</script>]]></text></svg>")
        XCTAssertFalse(doc.canonical.contains("<!--")); XCTAssertTrue(doc.canonical.contains("&lt;script&gt;"))
    }
    func testSVGClipboardMIMEAndPNGRepresentationPreferSVG() throws {
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem(); item.setData(Data(SVGFixtures.icon.utf8), forType: .init(SVGDocument.pasteboardType)); item.setData(Data([1,2]), forType: .png)
        pb.writeObjects([item])
        let clip = try XCTUnwrap(ClipboardReader.read(pb, source: "Tests", sourceID: "tests", exclusions: []))
        XCTAssertEqual(clip.kind, .text); XCTAssertEqual(clip.text, SVGFixtures.icon); XCTAssertEqual(clip.structuredFormat, .svg)
    }
    func testSVGMislabeledAsRasterNeverReachesNativeSVGPreview() throws {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let clip = Clip(title: "Fausse image", text: "", source: "Tests", sourceID: "tests", kind: .image, fingerprint: UUID().uuidString, payload: .init(representations: [[.init(type: type.rawValue, data: Data("<svg onload='alert(1)'/>".utf8))]]))
            XCTAssertNil(clip.image); XCTAssertNil(clip.previewImage(maxPixels: 640))
        }
    }
    func testMutationCorpusNeverAdmitsExecutableElements() throws {
        var count = 0
        for seed in [SVGFixtures.icon, "<svg><script>alert(1)</script></svg>", "<svg><rect onload='test()'/></svg>"] {
            let chars = Array(seed)
            for index in chars.indices {
                var mutation = chars; mutation.remove(at: index)
                if let document = try? SVGDocument.parse(String(mutation)) {
                    XCTAssertFalse(document.canonical.contains("<script")); XCTAssertFalse(document.canonical.contains("onload="))
                    XCTAssertNoThrow(try SVGDocument.parse(document.canonical))
                }
                count += 1
            }
        }
        print("SVG_MUTATIONS \(count)")
    }
    func testChildRendererProducesPixelsAndPreservesTransparency() async throws {
        let executable = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/out/Products/Release/EasyPaste")
        let document = try SVGDocument.parse(SVGFixtures.icon)
        let data = try await SVGRenderer.render(document, maxPixels: 240, executable: executable)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, 240); XCTAssertEqual(bitmap.pixelsHigh, 160)
        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertGreaterThan(bitmap.colorAt(x: 20, y: 80)?.alphaComponent ?? 0, 0.9)
        // colorAt returns a calibrated NSColor even for an sRGB bitmap. Check the
        // embedded profile and stored channels, without a second color conversion.
        XCTAssertEqual(bitmap.colorSpace, .sRGB)
        let color = try XCTUnwrap(bitmap.colorAt(x: 20, y: 80))
        XCTAssertEqual(color.redComponent, 155.0/255, accuracy: 1.0/255)
        XCTAssertEqual(color.greenComponent, 241.0/255, accuracy: 1.0/255)
        XCTAssertEqual(color.blueComponent, 203.0/255, accuracy: 1.0/255)
    }
    func testCancelledRendererReturnsWithoutBlocking() async throws {
        let document = try SVGDocument.parse(SVGFixtures.icon)
        let executable = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/out/Products/Release/EasyPaste")
        let task = Task { try await SVGRenderer.render(document, executable: executable) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled render must not publish") } catch { }
    }
    func testRendererFailureDoesNotCrashParent() async throws {
        let document = try SVGDocument.parse("<svg>" + String(repeating: "<rect width='1' height='1' fill='#9BF1CB'/>", count: 1900) + "</svg>")
        let start = Date()
        for path in ["/usr/bin/false", "/does-not-exist/EasyPaste"] {
            do { _ = try await SVGRenderer.render(document, executable: URL(fileURLWithPath: path)); XCTFail("Must reject missing or failed helper") } catch { }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testExtremeDimensionsAndRebuiltOutputBudget() {
        XCTAssertThrowsError(try SVGDocument.parse("<svg width='1e-310' height='1e-310'/>"))
        let expanded = "<svg><text><![CDATA[" + String(repeating: "<", count: 140_000) + "]]></text></svg>"
        XCTAssertLessThan(expanded.utf8.count, SVGDocument.inputLimit)
        XCTAssertThrowsError(try SVGDocument.parse(expanded))
    }
    func testUnresponsiveHelperIsKilledAtDeadline() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-render-test-" + UUID().uuidString)
        try "#!/bin/sh\ntrap '' TERM\nexec /bin/sleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let start = Date()
        do { _ = try await SVGRenderer.render(SVGDocument.parse(SVGFixtures.icon), executable: script); XCTFail("Timeout must not return an image") } catch { }
        XCTAssertLessThan(Date().timeIntervalSince(start), 12)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 5)
    }
    func testFileReaderRejectsOversizeAndPreservesSource() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Icon.SVG")
        XCTAssertTrue(SVGFile.isSVG(file.path)); XCTAssertFalse(SVGFile.isSVG("image.svg.png"))
        try SVGFixtures.icon.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try SVGFile.read(file), SVGFixtures.icon)
        try Data(repeating: 0, count: SVGDocument.inputLimit + 1).write(to: file)
        XCTAssertThrowsError(try SVGFile.read(file)); XCTAssertThrowsError(try SVGFile.read(folder))
        XCTAssertTrue(SVGFile.isSVG("image.SVGZ")); XCTAssertThrowsError(try SVGFile.read(folder.appendingPathComponent("image.svgz")))
    }
}

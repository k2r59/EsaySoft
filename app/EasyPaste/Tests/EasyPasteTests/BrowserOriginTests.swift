import AppKit
import XCTest
@testable import EasyPaste

final class BrowserOriginTests: XCTestCase {
    func testExtensionHTMLParsesEntitiesAndAttributeOrder() {
        let html = #"<!doctype html><html><head><meta content='https://example.com/page?a=1&amp;b=%22été%22&#38;c=&#x32;' name='easypaste-source-url'></head><body>Texte</body></html>"#
        XCTAssertEqual(BrowserOrigin.extensionURL(Data(html.utf8)), "https://example.com/page?a=1&b=%22%C3%A9t%C3%A9%22&c=2")
        XCTAssertEqual(BrowserOrigin.extensionURL(Data(#"<META NAME="easypaste-source-url" CONTENT="https://example.com/">"#.utf8)), "https://example.com/")
    }
    func testExtensionWinsOverChromiumPopupOriginAndPlainTextIsUntouched() throws {
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem(); item.setString("Texte inchangé", forType: .string)
        item.setString("https://wrong.example/", forType: BrowserOrigin.chromiumType)
        item.setString(#"<head><meta name="easypaste-source-url" content="https://page.example/"></head>"#, forType: .html)
        pb.writeObjects([item])
        let clip = try XCTUnwrap(ClipboardReader.read(pb, source: "Chrome", sourceID: "com.google.Chrome", exclusions: []))
        XCTAssertEqual(clip.sourceURL, "https://page.example/"); XCTAssertEqual(clip.text, "Texte inchangé")
        XCTAssertEqual(clip.metadata().sourceURL, clip.sourceURL)
    }
    func testNativeChromiumTextAndImageOriginsWithoutExtension() throws {
        for type in [NSPasteboard.PasteboardType.string, .png] {
            let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
            let item = NSPasteboardItem(); item.setData(Data("test".utf8), forType: type)
            item.setString("https://example.com/article", forType: BrowserOrigin.chromiumType); pb.writeObjects([item])
            XCTAssertEqual(try ClipboardReader.read(pb, source: "Chrome", sourceID: "com.google.Chrome", exclusions: [])?.sourceURL, "https://example.com/article")
        }
    }
    func testOrdinaryLinkAndHTMLLinksAreNotPageOrigins() throws {
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem(); item.setString("https://example.com/target", forType: .URL)
        item.setString(#"<a href="https://other.example/">link</a><img src="https://image.example/a.png">"#, forType: .html)
        pb.writeObjects([item])
        XCTAssertNil(try ClipboardReader.read(pb, source: "Chrome", sourceID: "com.google.Chrome", exclusions: [])?.sourceURL)
    }
    func testUnsafeConflictingAndMalformedSourcesAreRejected() {
        for value in ["javascript:alert(1)", "file:///etc/hosts", "data:text/html,x", "chrome-extension://abcd/popup.html", "https://user:secret@example.com/", "https://example.com/\nfoo", "https:///", String(repeating: "a", count: 8193)] { XCTAssertNil(BrowserOrigin.url(value), value) }
        for html in [
            #"<meta name="easypaste-source-url" content="javascript:alert(1)">"#,
            #"<meta name="easypaste-source-url" content="https://a.example"><meta name="easypaste-source-url" content="https://b.example">"#,
            #"<meta name="easypaste-source-url" content="https://a.example" content="https://b.example">"#,
            #"<!-- <meta name="easypaste-source-url" content="https://a.example"> -->"#,
            #"<body><meta name="easypaste-source-url" content="https://a.example">"#,
            String(repeating: " ", count: 65_536) + #"<meta name="easypaste-source-url" content="https://a.example">"#
        ] { XCTAssertNil(BrowserOrigin.extensionURL(Data(html.utf8))) }
    }
    func testOldHistoryDecodesWithoutSourceAndRoundTripsNewSource() throws {
        let payload = ClipPayload(representations: [])
        var clip = Clip(title: "Ancienne copie", text: "Texte", source: "Notes", sourceID: "test", kind: .text, fingerprint: "x", payload: payload)
        XCTAssertNil(try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip)).sourceURL)
        clip.sourceURL = "https://example.com/"
        XCTAssertEqual(try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip)).originURL?.absoluteString, clip.sourceURL)
        clip.sourceURL = "javascript:alert(1)"; XCTAssertNil(clip.originURL)
    }
    func testCaptureOriginOnlyForSamePageAndWindowContainedRegion() {
        let context = BrowserPageContext(sourceURL: "https://example.com/", frame: CGRect(x: -1000, y: 25, width: 900, height: 700))
        let rect = CGRect(x: -800, y: 100, width: 200, height: 200)
        XCTAssertEqual(context.source(for: rect, confirmed: context), context.sourceURL)
        XCTAssertNil(context.source(for: CGRect(x: 0, y: 0, width: 300, height: 300), confirmed: context))
        XCTAssertNil(context.source(for: rect, confirmed: nil))
        XCTAssertNil(context.source(for: rect, confirmed: BrowserPageContext(sourceURL: "https://other.example/", frame: context.frame)))
        XCTAssertNil(context.source(for: rect, confirmed: BrowserPageContext(sourceURL: context.sourceURL, frame: context.frame.offsetBy(dx: 1, dy: 0))))
    }
    func testMetadataScanStaysBoundedOnLargeHTML() {
        let data = Data(String(repeating: "<p>long content</p>", count: 300_000).utf8)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 { XCTAssertNil(BrowserOrigin.extensionURL(data)) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1, "Only a bounded HTML prefix should be scanned")
    }
    func testLongSourceURLSurvivesAttributeEntityExpansionWithinBoundedHead() throws {
        let prefix = "https://example.com/?q="
        let source = prefix + String(repeating: "&", count: 8192 - prefix.utf8.count)
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;")
        let html = "<html><head><meta name=\"easypaste-source-url\" content=\"\(escaped)\"></head><body>Texte</body></html>"
        XCTAssertGreaterThan(html.utf8.count, 40_000)
        XCTAssertEqual(BrowserOrigin.extensionURL(Data(html.utf8)), source)
        XCTAssertNil(BrowserOrigin.url(source + "x"))
        let ordinary = prefix + String(repeating: "a", count: 5000)
        XCTAssertEqual(BrowserOrigin.extensionURL(Data("<meta name='easypaste-source-url' content='\(ordinary)'>".utf8)), ordinary)
    }
    func testMetadataIgnoresCommentsRawElementsTemplatesAndQuotedTagLiterals() {
        let fake = #"<meta name="easypaste-source-url" content="https://wrong.example/">"#
        let real = #"<meta name="easypaste-source-url" content="https://real.example/">"#
        for wrapped in [
            "<!-- \(fake) -->",
            "<script>const example = '\(fake)';</script>",
            "<SCRIPT type='module'>const example = '\(fake)';</ScRiPt >",
            "<style>.example::before { content: '\(fake)'; }</style>",
            "<title>\(fake)</title>",
            "<noscript>\(fake)</noscript>",
            "<template>Text<template>\(fake)</template>After</template>",
            "<link data-example='quoted > \(fake)' href='https://example.com/style.css'>"
        ] {
            XCTAssertNil(BrowserOrigin.extensionURL(Data("<head>\(wrapped)</head>".utf8)), wrapped)
            XCTAssertEqual(BrowserOrigin.extensionURL(Data("<head>\(wrapped)\(real)</head>".utf8)), "https://real.example/", wrapped)
        }
    }
    func testMetadataScannerRejectsUnclosedOrBodyContentAndHandlesQuotedGreaterThan() {
        let real = #"<meta name="easypaste-source-url" content="https://real.example/">"#
        for prefix in ["<!-- ", "<script> ", "<style> ", "<template> ", "<body>", "<p>", "ordinary text ", "<head><link data-example='"] {
            XCTAssertNil(BrowserOrigin.extensionURL(Data((prefix + real).utf8)), prefix)
        }
        let html = #"<head><meta data-label='a > b < c' content='https://real.example/?a=1&#X26;b=2' name='easypaste-source-url'></head>"#
        XCTAssertEqual(BrowserOrigin.extensionURL(Data(html.utf8)), "https://real.example/?a=1&b=2")
        XCTAssertEqual(BrowserOrigin.extensionURL(Data("<META NAME=easypaste-source-url CONTENT=https://real.example/>".utf8)), "https://real.example/")
    }
}

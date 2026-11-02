import AppKit
import ApplicationServices
import XCTest
@testable import EasyPaste

final class PasteCompatibilityTests: XCTestCase {
    func testSecureInputPreservesUnicodeWithoutCommandOrReturnEvents() throws {
        let text = String(repeating: "été😀_123456789", count: 3)
        let events = try XCTUnwrap(PasteCompatibilityPolicy.secureInput(text))
        var decoded = ""
        for index in stride(from: 0, to: events.count, by: 2) {
            XCTAssertEqual(events[index].type, .keyDown)
            XCTAssertEqual(events[index + 1].type, .keyUp)
            for event in [events[index], events[index + 1]] { XCTAssertTrue(event.flags.isEmpty) }
            var units = [UniChar](repeating: 0, count: 32), count = 0
            events[index].keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &count, unicodeString: &units)
            XCTAssertLessThanOrEqual(count, 16)
            decoded += String(decoding: units.prefix(count), as: UTF16.self)
        }
        XCTAssertEqual(decoded, text)
        for invalid in ["", "a\nb", "a\tb", String(repeating: "a", count: 1_025)] { XCTAssertNil(PasteCompatibilityPolicy.secureInput(invalid)) }
    }
    func testFileZillaExceptionRequiresExactApplicationAndSiteManagerDialog() {
        XCTAssertFalse(PasteCompatibilityPolicy.fileZillaDialog(bundleID: "org.filezilla-project.filezilla", role: nil, title: "FileZilla"))
        XCTAssertFalse(PasteCompatibilityPolicy.fileZillaDialog(bundleID: "org.filezilla-project.filezilla", role: kAXStandardWindowSubrole, title: nil))
        for title in ["Gestionnaire de sites", "Site Manager"] {
            XCTAssertTrue(PasteCompatibilityPolicy.fileZillaDialog(bundleID: "org.filezilla-project.filezilla", role: kAXDialogSubrole, title: title))
            XCTAssertFalse(PasteCompatibilityPolicy.fileZillaDialog(bundleID: "com.apple.TextEdit", role: kAXDialogSubrole, title: title))
            XCTAssertFalse(PasteCompatibilityPolicy.fileZillaDialog(bundleID: "org.filezilla-project.filezilla", role: kAXStandardWindowSubrole, title: title))
        }
        for title in ["FileZilla", "Paramètres", "Gestionnaire de sites — Données incorrectes", ""] {
            XCTAssertFalse(PasteCompatibilityPolicy.fileZillaDialog(bundleID: "org.filezilla-project.filezilla", role: kAXDialogSubrole, title: title))
        }
    }
    func testSheetsExceptionIsOptInPlainPasteToActualSheetOnly() {
        let url = "https://docs.google.com/spreadsheets/d/test-id/edit#gid=0"
        for id in ["company.thebrowser.Browser", "com.google.Chrome", "org.mozilla.firefox", "com.apple.Safari"] {
            XCTAssertTrue(PasteCompatibilityPolicy.sheetsValues(bundleID: id, plain: true, pageURL: url))
            XCTAssertFalse(PasteCompatibilityPolicy.sheetsValues(bundleID: id, plain: false, pageURL: url))
        }
        XCTAssertFalse(PasteCompatibilityPolicy.sheetsValues(bundleID: "com.apple.TextEdit", plain: true, pageURL: url))
    }
    func testOtherPagesAndLookalikeURLsRetainStandardPaste() {
        let urls: [String?] = [nil, "", "https://docs.google.com/", "https://docs.google.com/document/d/test/edit",
            "https://docs.google.com/spreadsheets/", "https://docs.google.com/spreadsheets/d/",
            "https://docs.google.com/spreadsheets/d/e/published/pubhtml", "https://docs.google.com.evil.test/spreadsheets/d/test/edit",
            "https://evil.test/?url=https://docs.google.com/spreadsheets/d/test/edit", "http://docs.google.com/spreadsheets/d/test/edit",
            "https://user@docs.google.com/spreadsheets/d/test/edit", "https://docs.google.com:8443/spreadsheets/d/test/edit"]
        for url in urls { XCTAssertFalse(PasteCompatibilityPolicy.sheetsValues(bundleID: "company.thebrowser.Browser", plain: true, pageURL: url), url ?? "nil") }
    }
    func testInsertionPreservesExistingPrefixSuffixAndSelection() throws {
        let edit = try XCTUnwrap(PasteCompatibilityPolicy.inserting("test", into: "ftp.old.invalid", selection: NSRange(location: 4, length: 3)))
        XCTAssertEqual(edit.value, "ftp.test.invalid"); XCTAssertEqual(edit.cursor, 8)
        let insertion = try XCTUnwrap(PasteCompatibilityPolicy.inserting("abc", into: "xy", selection: NSRange(location: 1, length: 0)))
        XCTAssertEqual(insertion.value, "xabcy"); XCTAssertEqual(insertion.cursor, 4)
    }
    func testUnicodeSelectionUsesUTF16AndPreservesCharacters() throws {
        let edit = try XCTUnwrap(PasteCompatibilityPolicy.inserting("été", into: "😀old.txt", selection: NSRange(location: 2, length: 3)))
        XCTAssertEqual(edit.value, "😀été.txt"); XCTAssertEqual(edit.cursor, 5)
        XCTAssertNil(PasteCompatibilityPolicy.inserting("x", into: "😀abc", selection: NSRange(location: 1, length: 0)))
    }
    func testInvalidRangesAndControlCharactersNeverOverwriteField() {
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: -1, length: 0), NSRange(location: 8, length: 2)] {
            XCTAssertNil(PasteCompatibilityPolicy.inserting("x", into: "abc", selection: range))
        }
        for text in ["a\nb", "a\rb", "a\tb", "a\0b", String(repeating: "a", count: 65_537)] {
            XCTAssertNil(PasteCompatibilityPolicy.inserting(text, into: "abc", selection: NSRange(location: 0, length: 3)))
        }
    }
}

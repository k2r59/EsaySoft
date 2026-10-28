import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import EasyPaste

@MainActor final class SearchFocusTests: XCTestCase {
    private func fixture() -> (ShelfPanel, SearchTextField) {
        let panel = ShelfPanel(contentRect: CGRect(x: 50, y: 50, width: 480, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let field = SearchTextField(frame: CGRect(x: 20, y: 20, width: 300, height: 24))
        panel.contentView = NSView(frame: panel.contentLayoutRect)
        panel.contentView?.addSubview(field)
        return (panel, field)
    }

    func testRequestBeforeOpeningWaitsForTheKeyWindow() async throws {
        let (panel, field) = fixture(); defer { panel.close() }
        field.requestFocus()
        XCTAssertTrue(field.pendingFocus)
        panel.makeKeyAndOrderFront(nil)
        for _ in 0..<50 where field.currentEditor() == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(panel.firstResponder === field.currentEditor())
        XCTAssertNotNil(field.currentEditor())
        XCTAssertFalse(field.pendingFocus)
    }

    func testRepeatedReopeningAfterCardFocusLossRestoresTheRealEditor() async throws {
        let (panel, field) = fixture(); defer { panel.close() }
        for _ in 0..<8 {
            panel.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: SearchTextField.focusNotification, object: panel)
            XCTAssertNotNil(field.currentEditor())
            XCTAssertTrue(panel.firstResponder === field.currentEditor())
            panel.makeFirstResponder(nil)
            XCTAssertNil(field.currentEditor())
            panel.orderOut(nil)
        }
    }

    func testRequestForAnotherWindowNeverStealsFocus() {
        let (shelf, shelfField) = fixture(), (library, libraryField) = fixture()
        defer { shelf.close(); library.close() }
        shelf.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: SearchTextField.focusNotification, object: shelf)
        XCTAssertNotNil(shelfField.currentEditor())
        XCTAssertNil(libraryField.currentEditor())
        XCTAssertFalse(libraryField.pendingFocus)
        NotificationCenter.default.post(name: SearchTextField.focusNotification, object: nil)
        XCTAssertFalse(libraryField.pendingFocus, "Unscoped notifications must not wake hidden search fields")
    }

    func testPendingRequestDoesNotFocusAHiddenOrDetachedField() {
        let (panel, field) = fixture(); defer { panel.close() }
        field.isHidden = true
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(nil)
        field.requestFocus()
        XCTAssertTrue(field.pendingFocus)
        XCTAssertNil(field.currentEditor())
        field.removeFromSuperview()
        XCTAssertNil(field.window)
        NotificationCenter.default.post(name: SearchTextField.focusNotification, object: panel)
        XCTAssertNil(field.currentEditor())
    }

    func testNativeSearchEditsAndProgrammaticClearStayInSync() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "EasyPaste.search-binding." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let panel = ShelfPanel(contentRect: CGRect(x: 50, y: 50, width: 360, height: 70), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let host = NSHostingView(rootView: SearchBar(history: history, focusOnAppear: true, glass: true))
        panel.contentView = host; host.frame = CGRect(x: 0, y: 0, width: 360, height: 70)
        host.layoutSubtreeIfNeeded(); panel.makeKeyAndOrderFront(nil)
        func find(_ view: NSView) -> SearchTextField? {
            if let field = view as? SearchTextField { return field }
            return view.subviews.compactMap { find($0) }.first
        }
        let field = try XCTUnwrap(find(host))
        for _ in 0..<50 where field.currentEditor() == nil { try await Task.sleep(for: .milliseconds(10)) }
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Recherche française éà", replacementRange: NSRange(location: 0, length: 0))
        for _ in 0..<50 where history.query.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(history.query, "Recherche française éà")
        history.query = ""
        for _ in 0..<50 where !field.stringValue.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(field.stringValue, "")
        XCTAssertEqual(editor.string, "")
        XCTAssertTrue(panel.firstResponder === editor)
    }
}

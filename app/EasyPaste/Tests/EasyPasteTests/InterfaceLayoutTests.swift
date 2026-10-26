import XCTest
import SwiftUI
import CryptoKit
@testable import EasyPaste

@MainActor final class InterfaceLayoutTests: XCTestCase {
    func testAnnotationFitsMinimumWindow() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.95, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        let image = try XCTUnwrap(context.makeImage()), data = try CaptureImage.png(image)
        let model = AnnotationModel(data: data, image: image, size: CGSize(width: 800, height: 500))
        model.commit(AnnotationMark(tool: .arrow, start: CGPoint(x: 100, y: 180), end: CGPoint(x: 500, y: 70), color: .coral, width: 7))
        let view = AnnotationView(model: model, cancel: {}, save: { _, _ in })
        try check(view, size: CGSize(width: 1080, height: 700), name: "annotation-minimum")
    }
    func testLibraryFitsMinimumWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "EasyPaste.layout." + UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        try check(MainView(history: history), size: CGSize(width: 1050, height: 740), name: "library-minimum")
    }
    func testEverySettingsCategoryFitsMinimumWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "EasyPaste.settings.layout." + UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        for category in SettingsCategory.allCases {
            try check(SettingsView(history: history, initialCategory: category),
                      size: CGSize(width: 837, height: 740), name: "settings-\(category)")
        }
    }
    func testShelfCardsAndGlassFitBothSizesAndAccessibilityModes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "EasyPaste.shelf.layout." + UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let payload = ClipPayload(representations: [[ClipRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("Lisible sur tous les fonds".utf8))]])
        history.add(Clip(title: "Une idée à garder", text: "Lisible sur tous les fonds, même pendant le défilement.", source: "Notes", sourceID: "test", kind: .text, fingerprint: Clip.fingerprint(payload), payload: payload))
        await history.flush()
        for _ in 0..<100 where history.visible.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let clip = try XCTUnwrap(history.visible.first)
        for _ in 0..<15 { history.recordPaste([clip]) }
        await history.flush()
        history.enabled = true
        for compact in [false, true] {
            history.compact = compact
            history.surface = "shelf"; history.shelfScreenHeight = 768
            for expanded in [false, true] {
                history.shelfPreview = expanded ? clip : nil
                let layout = ShelfLayout(screenHeight: 768, compact: compact, expanded: expanded)
                try check(ShelfRootView(history: history), size: CGSize(width: 1120, height: layout.height), name: "shelf-\(compact)-\(expanded)")
                history.recentlyTrashed = [UUID()]
                let footerLayout = ShelfLayout(screenHeight: 768, compact: compact, expanded: expanded, footer: true)
                try check(ShelfRootView(history: history), size: CGSize(width: 1120, height: footerLayout.height), name: "shelf-footer-\(compact)-\(expanded)")
                history.recentlyTrashed = []
            }
            try check(ClipCard(history: history, clip: clip, compact: compact, quickIndex: 0).foregroundStyle(Theme.ink).frame(width: compact ? 215 : 252), size: CGSize(width: compact ? 215 : 252, height: compact ? 145 : 215), name: "card-\(compact ? "compact" : "normal")")
        }
        try check(ShelfGlassSurface(opaque: true), size: CGSize(width: 1400, height: 290), name: "shelf-opaque")
        try check(LibraryClipCard(history: history, clip: clip).foregroundStyle(Theme.ink).frame(width: 235), size: CGSize(width: 235, height: 252), name: "library-card")
        try check(LibraryClipCard(history: history, clip: clip, list: true).foregroundStyle(Theme.ink), size: CGSize(width: 780, height: 91), name: "library-row")
    }
    private func check<V: View>(_ root: V, size: CGSize, name: String) throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try check(root, size: size, name: name, appearance: appearance)
        }
    }
    private func check<V: View>(_ root: V, size: CGSize, name: String, appearance: NSAppearance.Name) throws {
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size); host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, size.width, "The interface must fit the supported minimum width.")
        // The shelf has no vertical scrolling; the library/settings and annotation
        // inspector intentionally expose content taller than their scroll viewport.
        if name.hasPrefix("shelf-") || name.hasPrefix("card-") {
            XCTAssertLessThanOrEqual(host.fittingSize.height, size.height, "The shelf must fit its fixed height.")
        }
        if let folder = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
            let url = URL(fileURLWithPath: folder); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(name+"-"+appearance.rawValue+".png"))
        }
    }
}

import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import EasyPaste

@MainActor final class ShelfPreviewTests: XCTestCase {
    private var directory: URL!
    private var history: History!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "EasyPaste.shelf-preview." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        for value in ["Premier", "Deuxième", "Troisième"] { history.add(clip(value)) }
        await history.flush()
        for _ in 0..<100 where history.visible.count != 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(history.visible.count, 3)
    }
    override func tearDown() async throws {
        await history.flush(); history = nil
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }
    private func clip(_ text: String) -> Clip {
        let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]])
        return Clip(title: String(text.prefix(40)), text: text, source: "Essai", sourceID: "test", kind: .text, fingerprint: Clip.fingerprint(payload), payload: payload)
    }
    func testQuickPreviewNeverPresentsASeparateWindowAndFollowsNavigation() {
        history.surface = "shelf"
        history.previewChanged = { _ in XCTFail("Quick previews must remain inside the shelf") }
        var resizes = 0
        history.resizeShelf = { resizes += 1 }
        history.openPreview(history.visible[0])
        XCTAssertNil(history.previewing)
        XCTAssertEqual(history.shelfPreview?.id, history.visible[0].id)
        XCTAssertEqual(resizes, 1)
        history.moveSelection(1); history.followShelfSelection()
        XCTAssertEqual(history.shelfPreview?.id, history.visible[1].id)
        XCTAssertEqual(resizes, 1, "Navigating must not resize the window")
        history.shelfPreview = nil
        XCTAssertEqual(resizes, 2)
        history.moveSelection(1); history.followShelfSelection()
        XCTAssertNil(history.shelfPreview, "An ordinary selection must not reopen the preview")
    }
    func testLibraryPreviewRetainsItsOwnWindow() {
        history.surface = "library"
        var shown: UUID?
        history.previewChanged = { shown = $0?.id }
        let item = history.visible[0]
        history.openPreview(item)
        XCTAssertEqual(shown, item.id)
        XCTAssertNil(history.shelfPreview)
    }
    func testResetDuringDiskReadNeverRestoresOldPreview() async {
        let model = ShelfPreviewModel(), item = history.visible[0]
        let loading = Task { await model.load(item, history: history) }
        await Task.yield()
        model.reset()
        await loading.value
        XCTAssertNil(model.full)
        XCTAssertNil(model.player)
        XCTAssertTrue(model.text.isEmpty)
    }
    func testRapidNavigationOnlyPublishesLatestClip() async {
        let model = ShelfPreviewModel(), first = history.visible[0], last = history.visible[2]
        let older = Task { await model.load(first, history: history) }
        await Task.yield()
        await model.load(last, history: history)
        await older.value
        XCTAssertEqual(model.full?.id, last.id)
        XCTAssertEqual(model.text, last.text)
    }
    func testLargePreviewIsBoundedButCopyPreservesOriginal() async throws {
        let text = String(repeating: "Texte complet à conserver. ", count: 14000)
        let item = clip(text); history.add(item); await history.flush()
        let model = ShelfPreviewModel()
        await model.load(item, history: history)
        XCTAssertLessThanOrEqual(model.text.utf8.count, StructuredText.displayLimit)
        XCTAssertFalse(model.note.isEmpty)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let copied = await history.copy([item], to: pb, sound: nil)
        XCTAssertTrue(copied)
        XCTAssertEqual(pb.string(forType: .string), text)
        model.reset(); XCTAssertNil(model.full)
    }
    func testMalformedStructuredTextRemainsReadableAndUnchanged() async {
        let item = clip("{\"clé\": [1, }")
        history.add(item); await history.flush()
        let model = ShelfPreviewModel(); await model.load(item, history: history)
        XCTAssertEqual(model.text, item.text)
        XCTAssertNil(model.result)
        XCTAssertFalse(model.note.isEmpty)
        XCTAssertTrue(model.error.isEmpty)
    }
    func testShapeIsContinuousAndCornersOutsidePreviewStayTransparent() {
        for screen in [CGFloat(600), 768, 900, 1440] {
            for compact in [false, true] {
                let layout = ShelfLayout(screenHeight: screen, compact: compact, expanded: true)
                XCTAssertLessThanOrEqual(layout.height, screen - 24)
                XCTAssertGreaterThan(layout.previewHeight, 100)
                let rect = CGRect(x: 0, y: 0, width: 1400, height: layout.height)
                let shape = ShelfOutline(previewHeight: layout.previewHeight, previewWidth: ShelfLayout.previewWidth(in: rect.width)).path(in: rect)
                XCTAssertTrue(shape.contains(CGPoint(x: 700, y: 30)))
                XCTAssertTrue(shape.contains(CGPoint(x: 700, y: layout.previewHeight)))
                XCTAssertTrue(shape.contains(CGPoint(x: 40, y: layout.previewHeight + 40)))
                XCTAssertFalse(shape.contains(CGPoint(x: 40, y: 40)))
                XCTAssertEqual(shape.boundingRect, rect)
            }
        }
    }
    func testInsetRimsStayEquidistantAcrossConvexAndConcaveCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 1400, height: 920)
        let shape = ShelfOutline(previewHeight: 600, previewWidth: 700)
        let outer = shape.path(in: bounds)
        // SwiftUI Path.contains flattens curves coarsely; Core Graphics tests
        // the emitted curve rather than its low-resolution hit-test outline.
        func crossing(_ path: Path, centre: CGPoint, angle: Double, startsInside: Bool) -> CGFloat {
            let precise = path.cgPath
            let radians = angle * .pi / 180
            var low: CGFloat = 0, high: CGFloat = 100
            for _ in 0..<24 {
                let distance = (low + high) / 2
                let point = CGPoint(x: centre.x + distance * cos(radians), y: centre.y + distance * sin(radians))
                if precise.contains(point) == startsInside { low = distance } else { high = distance }
            }
            return (low + high) / 2
        }
        for inset in [CGFloat(2.7), 4, 5.25] {
            let inner = shape.inset(by: inset).path(in: bounds)
            for angle in [-80.0, -60, -45, -30, -10] {
                let centre = CGPoint(x: 1014, y: 36)
                let gap = crossing(outer, centre: centre, angle: angle, startsInside: true) - crossing(inner, centre: centre, angle: angle, startsInside: true)
                XCTAssertEqual(gap, inset, accuracy: 0.02, "Uneven convex rim at \(angle)°")
            }
            for angle in [100.0, 120, 135, 150, 170] {
                let centre = CGPoint(x: 1108, y: 542)
                let gap = crossing(inner, centre: centre, angle: angle, startsInside: false) - crossing(outer, centre: centre, angle: angle, startsInside: false)
                XCTAssertEqual(gap, inset, accuracy: 0.02, "Uneven concave rim at \(angle)°")
            }
        }
    }

    func testRimsStayInsideTheirBoundsDuringExpansionAndOnNarrowWidths() {
        for width in [CGFloat(48), 360, 500, 1120] {
            for stem in [CGFloat(48), 320, width] {
                for height in [CGFloat(0), 0.5, 1, 2, 4, 8, 12, 40, 100, 600] {
                    let bounds = CGRect(x: 0, y: 0, width: width, height: height + 320)
                    for inset in [CGFloat(0), 2.7, 4, 5.25] {
                        let path = ShelfOutline(previewHeight: height, previewWidth: stem).inset(by: inset).path(in: bounds)
                        let box = path.cgPath.boundingBoxOfPath
                        let allowed = bounds.insetBy(dx: inset, dy: inset).insetBy(dx: -0.02, dy: -0.02)
                        XCTAssertFalse(box.isNull)
                        XCTAssertTrue(allowed.contains(box), "Rim escapes its bounds: width \(width), stem \(stem), height \(height), inset \(inset): \(box)")
                    }
                }
            }
        }
    }

}

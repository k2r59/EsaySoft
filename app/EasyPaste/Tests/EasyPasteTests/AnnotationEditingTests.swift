import XCTest
import AppKit
import Combine
@testable import EasyPaste

final class AnnotationEditingTests: XCTestCase {
    private func fixture() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 360, height: 240, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 360, height: 240))
        return try CaptureImage.png(XCTUnwrap(context.makeImage()))
    }
    @MainActor private func model() throws -> AnnotationModel {
        let data = try fixture(), decoded = try AnnotationModel.prepare(data)
        return AnnotationModel(data: data, image: decoded.0, size: decoded.1)
    }
    private func arrow() -> AnnotationMark { AnnotationMark(tool: .arrow, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 100, y: 90), color: .coral, width: 4) }

    func testHitTestingUsesShapeRatherThanArrowBoundingBox() {
        XCTAssertTrue(arrow().contains(CGPoint(x: 60, y: 61), tolerance: 4))
        XCTAssertFalse(arrow().contains(CGPoint(x: 20, y: 90), tolerance: 4))
        var rectangle = arrow(); rectangle.tool = .rectangle
        XCTAssertTrue(rectangle.contains(CGPoint(x: 20, y: 60), tolerance: 4))
        XCTAssertFalse(rectangle.contains(CGPoint(x: 60, y: 60), tolerance: 4))
        rectangle.tool = .highlight
        XCTAssertTrue(rectangle.contains(CGPoint(x: 60, y: 60), tolerance: 4))
    }
    @MainActor func testMoveClampsToImageKeepsIdentityAndIsUndoable() throws {
        let model = try model(), mark = arrow()
        model.commit(mark); model.select(mark.id)
        model.nudge(dx: -100, dy: -100)
        let moved = try XCTUnwrap(model.selectedMark)
        XCTAssertEqual(moved.id, mark.id); XCTAssertEqual(moved.start, .zero)
        XCTAssertEqual(moved.end, CGPoint(x: 80, y: 60))
        model.undo(); XCTAssertEqual(model.selectedMark, mark)
        model.redo(); XCTAssertEqual(model.selectedMark, moved)
        model.nudge(dx: 1000, dy: 1000)
        XCTAssertEqual(model.selectedMark?.bounds.maxX, 360)
        XCTAssertEqual(model.selectedMark?.bounds.maxY, 240)
    }
    @MainActor func testSliderGestureCreatesOneUndoStepAndRestoresInspector() throws {
        let model = try model(), mark = arrow()
        model.commit(mark); model.select(mark.id); model.beginStyleEdit()
        for width in 5...20 { model.changeWidth(CGFloat(width)) }
        model.endStyleEdit()
        XCTAssertEqual(model.undoStates.count, 2)
        XCTAssertEqual(model.selectedMark?.width, 20)
        model.undo(); XCTAssertEqual(model.selectedMark?.width, 4); XCTAssertEqual(model.width, 4)
        model.redo(); XCTAssertEqual(model.width, 20)
        model.changeColor(.mint); XCTAssertEqual(model.selectedMark?.color, .mint)
        model.undo(); XCTAssertEqual(model.color, .coral)
        model.changeArrowhead(.dot); XCTAssertEqual(model.selectedMark?.arrowhead, .dot)
        model.undo(); XCTAssertEqual(model.arrowhead, .open)
    }
    @MainActor func testTextEditingReplacesSelectedTextAndDeleteCanBeUndone() throws {
        let model = try model()
        model.textPoint = CGPoint(x: 12, y: 20); model.text = "Avant"; model.addText()
        let mark = try XCTUnwrap(model.selectedMark)
        model.select(mark.id); model.editSelectedText(); model.text = "Après"; model.addText()
        XCTAssertEqual(model.snapshot.marks.count, 1); XCTAssertEqual(model.selectedMark?.id, mark.id)
        XCTAssertEqual(model.selectedMark?.text, "Après")
        model.undo(); XCTAssertEqual(model.selectedMark?.text, "Avant")
        model.deleteSelection(); XCTAssertTrue(model.snapshot.marks.isEmpty); XCTAssertNil(model.selectedID)
        model.undo(); XCTAssertEqual(model.snapshot.marks, [mark])
    }
    @MainActor func testSaveGuardAndEmptyTextToolSwitch() throws {
        let model = try model(), mark = arrow()
        model.commit(mark); model.saving = true
        model.changeColor(.mint); model.changeWidth(20); model.deleteSelection(); model.nudge(dx: 15, dy: 20)
        XCTAssertEqual(model.snapshot.marks, [mark])
        model.saving = false; model.textPoint = .zero; model.text = " "
        model.chooseTool(.pencil); XCTAssertNil(model.textPoint); XCTAssertNil(model.editingTextID)
        model.undo(); XCTAssertFalse(model.dirty)
    }
    func testPencilTranslationAndDifferentArrowheadsExportNativePNG() throws {
        let data = try fixture()
        let pencil = AnnotationMark(tool: .pencil, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 80, y: 20), color: .mint, width: 6, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 50), CGPoint(x: 80, y: 20)])
        XCTAssertTrue(pencil.contains(CGPoint(x: 40, y: 50), tolerance: 3))
        XCTAssertFalse(pencil.contains(CGPoint(x: 10, y: 45), tolerance: 3))
        let moved = pencil.translated(by: CGSize(width: 20, height: 10), within: CGSize(width: 360, height: 240))
        XCTAssertEqual(moved.points[1], CGPoint(x: 60, y: 60))
        let baseline = try AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot())
        XCTAssertNotEqual(try AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot(marks: [pencil])), baseline)
        var outputs = Set<Data>()
        for style in AnnotationArrowhead.allCases {
            var mark = arrow(); mark.arrowhead = style
            let output = try AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot(marks: [mark]))
            let image = try ImageRaster.decode(output).0
            XCTAssertEqual(image.width, 360); XCTAssertEqual(image.height, 240); outputs.insert(output)
        }
        XCTAssertEqual(outputs.count, AnnotationArrowhead.allCases.count)
    }
    @MainActor func testZoomDoesNotChangeExportAndUndoHistoryIsBounded() throws {
        let model = try model(), mark = arrow()
        model.commit(mark); let before = try AnnotationRenderer.export(data: model.data, snapshot: model.snapshot)
        model.zoom = 2
        let view = AnnotationCanvasView(model: model); view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(view.imageRect.width, 720)
        XCTAssertEqual(before, try AnnotationRenderer.export(data: model.data, snapshot: model.snapshot))
        model.select(mark.id)
        for _ in 0..<140 { model.nudge(dx: 1, dy: 0) }
        XCTAssertEqual(model.undoStates.count, 100); XCTAssertEqual(model.snapshot.marks.count, 1)
    }
    @MainActor func testPointerDraftDoesNotRepublishSidebarAndCommitsOnce() throws {
        let model = try model(), mark = arrow()
        model.commit(mark); model.select(mark.id)
        let view = AnnotationCanvasView(model: model); view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rect = view.imageRect, ratio = rect.width/model.size.width
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: rect.minX+point.x*ratio, y: rect.maxY-point.y*ratio), modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 60, y: 60)))
        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        for offset in 1...20 { view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 60+offset, y: 60))) }
        XCTAssertEqual(publications, 0); XCTAssertEqual(model.snapshot.marks, [mark])
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 80, y: 60)))
        XCTAssertEqual(try XCTUnwrap(model.selectedMark).start.x, 40, accuracy:0.000001); XCTAssertEqual(model.undoStates.count, 2)
        withExtendedLifetime(observation) {}
        let moved = try XCTUnwrap(model.selectedMark)
        view.mouseDown(with: event(.leftMouseDown, moved.end))
        view.mouseUp(with: event(.leftMouseUp, moved.start))
        XCTAssertEqual(model.selectedMark, moved, "A collapsed endpoint must not erase the shape.")
        XCTAssertNil(model.draft)
    }
}

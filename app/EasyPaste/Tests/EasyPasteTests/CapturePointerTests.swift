import AppKit
import XCTest
@testable import EasyPaste

@MainActor final class CapturePointerTests: XCTestCase {
    func testCursorHasCenteredHotspotAndTracksNonKeyWindows() {
        XCTAssertEqual(SelectionView.captureCursor.hotSpot, NSPoint(x: 18, y: 18))
        let view = SelectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.updateTrackingAreas()
        XCTAssertTrue(view.trackingAreas.contains { $0.options.contains([.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag]) })
        XCTAssertTrue(view.trackingAreas.contains { $0.options.contains([.cursorUpdate, .activeInActiveApp]) })
        XCTAssertFalse(view.trackingAreas.contains { $0.options.contains([.cursorUpdate, .activeAlways]) })
        view.updatePointer(at: NSPoint(x: 610, y: 466))
        XCTAssertEqual(view.pointerCoordinates, "610\n134")
        XCTAssertTrue(NSCursor.current === SelectionView.captureCursor)
    }

    func testPointerRemainsVisibleAtAllScreenEdgesAndStopsAfterCancel() {
        let view = SelectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        for point in [NSPoint(x: 0, y: 0), NSPoint(x: 799, y: 599), NSPoint(x: 0, y: 599), NSPoint(x: 799, y: 0)] {
            view.updatePointer(at: point)
            XCTAssertNotNil(view.pointerCoordinates)
            XCTAssertTrue(view.bounds.contains(view.pointerLabelFrame))
        }
        view.updatePointer(at: NSPoint(x: -1, y: 100))
        XCTAssertNil(view.pointerCoordinates)
        view.cancel()
        view.updatePointer(at: NSPoint(x: 100, y: 100))
        XCTAssertNil(view.pointerCoordinates)
    }

    func testCrossDisplayCoordinatesIncludingDragOutsideOriginalWindow() throws {
        let frames = [NSRect(x: 0, y: 0, width: 800, height: 600),
                      NSRect(x: -1000, y: 0, width: 1000, height: 700),
                      NSRect(x: 0, y: 600, width: 900, height: 700)]
        let windows = frames.map { frame -> SelectionWindow in
            let w = SelectionWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = SelectionView(frame: NSRect(origin: .zero, size: frame.size))
            return w
        }
        defer { windows.forEach { $0.close() }; NSCursor.arrow.set() }
        for w in windows {
            w.pointerMoved = { point in
                for target in windows {
                    let view = target.contentView as! SelectionView
                    view.updatePointer(at: view.convert(target.convertPoint(fromScreen: point), from: nil))
                }
            }
        }
        for (index, frame) in frames.enumerated() {
            let global = NSPoint(x: frame.minX + 100, y: frame.maxY - 150)
            // AppKit keeps delivering a drag to the window where it began.
            windows[0].pointerMoved?(global)
            for (i, window) in windows.enumerated() {
                let view = window.contentView as! SelectionView
                XCTAssertEqual(view.pointerCoordinates, i == index ? "100\n150" : nil)
            }
            XCTAssertTrue(NSCursor.current === SelectionView.captureCursor)
        }
    }
}

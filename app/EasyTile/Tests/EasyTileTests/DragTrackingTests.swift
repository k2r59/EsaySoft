import XCTest
@testable import EasyTile

final class DragTrackingTests: XCTestCase {
    private let initial = CGRect(x:100,y:100,width:800,height:600)

    func testEventBurstHasBoundedWorkAndMouseUpAlwaysUsesLatestSample() {
        var gate = DragFrameGate()
        var rendered: [Int] = []
        for event in 0..<1000 {
            if gate.allows(Double(event)/1000,interval:1.0/60) { rendered.append(event) }
        }
        XCTAssertEqual(rendered.first,0)
        XCTAssertLessThanOrEqual(rendered.count,60)
        XCTAssertGreaterThanOrEqual(rendered.count,58)
        // A release between display intervals must use its own location,
        // not the last rendered target. There is no queued replay afterwards.
        XCTAssertTrue(gate.allows(0.9991,interval:1.0/60,force:true))
        XCTAssertFalse(gate.allows(0.9992,interval:1.0/60))
        gate = DragFrameGate()
        XCTAssertTrue(gate.allows(0.9993,interval:1.0/60))
    }

    func testSmallPointerMotionDoesNotContactAnotherApplication() {
        var drag = DragTracking(initialPointer:.zero,initialFrame:initial)
        XCTAssertEqual(drag.update(pointer:CGPoint(x:8,y:8)) { XCTFail("Unnecessary AX read"); return nil },.pending)
    }

    func testContentDragDoesNotOpenPalette() {
        var drag = DragTracking(initialPointer:.zero,initialFrame:initial)
        for x in stride(from:20,through:300,by:20) {
            XCTAssertEqual(drag.update(pointer:CGPoint(x:x,y:40)) { self.initial },.pending)
        }
    }

    func testResizeCancelsEvenWhenTopLeftMoves() {
        var drag = DragTracking(initialPointer:.zero,initialFrame:initial)
        var resized = initial.offsetBy(dx:20,dy:20); resized.size.width -= 20
        XCTAssertEqual(drag.update(pointer:CGPoint(x:20,y:20)) { resized },.cancelled)
        XCTAssertEqual(drag.update(pointer:CGPoint(x:50,y:50)) { XCTFail("Cancelled drag queried window"); return nil },.cancelled)
    }

    func testUnavailableWindowCancelsBeforeConfirmation() {
        var drag = DragTracking(initialPointer:.zero,initialFrame:initial)
        XCTAssertEqual(drag.update(pointer:CGPoint(x:30,y:30)) { nil },.cancelled)
    }

    func testDelayedWindowMovementCanStillStartWhilePointerRests() {
        var drag = DragTracking(initialPointer:.zero,initialFrame:initial)
        let pointer = CGPoint(x:30,y:30)
        XCTAssertEqual(drag.update(pointer:pointer) { self.initial },.pending)
        XCTAssertEqual(drag.update(pointer:pointer) { self.initial.offsetBy(dx:20,dy:20) },.moving)
    }

    func testConfirmedDragNeverWaitsForRemoteWindowDuringHover() {
        var drag = DragTracking(initialPointer:.zero,initialFrame:initial)
        var reads = 0
        XCTAssertEqual(drag.update(pointer:CGPoint(x:30,y:30)) { reads += 1; return self.initial.offsetBy(dx:20,dy:20) },.moving)
        for x in 0..<10_000 {
            XCTAssertEqual(drag.update(pointer:CGPoint(x:x % 1000,y:x % 700)) {
                reads += 1; return nil // A slow/unresponsive remote window must not block hover.
            },.moving)
        }
        XCTAssertEqual(reads,1)
    }

    func testHoverOnlyUpdatesOnDestinationChangeAndClearsInGaps() {
        let geometry = DragPaletteGeometry(columns:8,count:8)
        let layouts = TileLayout.presets
        var hover = DragHover()
        let left = geometry.zoneFrame(layoutIndex:0,zone:layouts[0].zones[0])
        let right = geometry.zoneFrame(layoutIndex:0,zone:layouts[0].zones[1])
        let first = CGPoint(x:left.midX,y:left.midY)
        XCTAssertTrue(hover.sample(first)); XCTAssertFalse(hover.sample(first))
        XCTAssertTrue(hover.select(geometry.hit(first,layouts:layouts)))
        XCTAssertFalse(hover.select(geometry.hit(CGPoint(x:left.midX+1,y:left.midY),layouts:layouts)))
        XCTAssertTrue(hover.select(geometry.hit(CGPoint(x:right.midX,y:right.midY),layouts:layouts)))
        XCTAssertEqual(hover.choice,DragChoice(layoutIndex:0,zoneIndex:1))
        XCTAssertTrue(hover.select(geometry.hit(CGPoint(x:1,y:1),layouts:layouts)))
        XCTAssertNil(hover.choice)
        XCTAssertFalse(hover.select(nil))
        XCTAssertTrue(hover.select(geometry.hit(first,layouts:layouts)))
    }

    func testNewScreenOrDragResetsDestinationEvenForSameZone() {
        var hover = DragHover()
        let choice = DragChoice(layoutIndex:0,zoneIndex:0)
        XCTAssertTrue(hover.select(choice))
        hover = DragHover()
        XCTAssertTrue(hover.select(choice))
    }

    func testRapidBackAndForthKeepsLatestDestinationWithoutQueuing() {
        let geometry = DragPaletteGeometry(columns:8,count:8)
        let layouts = TileLayout.presets
        let frames = layouts[0].zones.map { geometry.zoneFrame(layoutIndex:0,zone:$0) }
        var hover = DragHover()
        let start = Date()
        for index in 0..<10_000 {
            let zone = index % frames.count, frame = frames[zone]
            XCTAssertTrue(hover.select(geometry.hit(CGPoint(x:frame.midX,y:frame.midY),layouts:layouts)))
            XCTAssertEqual(hover.choice,DragChoice(layoutIndex:0,zoneIndex:zone))
        }
        print("DRAG_HOVER_BENCH 10000 transitions: \(Date().timeIntervalSince(start))s")
    }
}

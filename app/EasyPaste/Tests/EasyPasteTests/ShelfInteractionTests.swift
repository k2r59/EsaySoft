import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import EasyPaste

@MainActor final class ShelfInteractionTests: XCTestCase {
    func testWheelRoutingAcrossCardBodiesAndGaps() async throws {
        for compact in [false, true] {
            for expanded in [false, true] { try await checkWheelRouting(compact: compact, expanded: expanded) }
        }
    }

    func testLineWheelRoutingAcrossGapHeights() async throws {
        for compact in [false, true] {
            for expanded in [false, true] {
                for fraction: CGFloat in [0.08, 0.92] {
                    try await checkWheelRouting(compact: compact, expanded: expanded, units: .line, yFraction: fraction)
                }
            }
        }
    }

    func testShiftVerticalWheelAcrossCardsAndGaps() async throws {
        for compact in [false, true] {
            for expanded in [false, true] {
                try await checkWheelRouting(compact: compact, expanded: expanded, units: .line, shiftVertical: true)
            }
        }
    }

    func testShiftWheelRowRoutingIncludingAlreadyHorizontalEvents() async throws {
        for compact in [false, true] {
            for expanded in [false, true] {
                for vertical in [false, true] {
                    try await checkWheelRouting(compact: compact, expanded: expanded, units: .line,
                        shiftVertical: vertical, routeRow: true)
                }
            }
        }
    }

    func testPreciseShiftWheelThroughWindowAcrossCardsAndGaps() async throws {
        for compact in [false, true] {
            for expanded in [false, true] {
                for vertical in [false, true] {
                    try await checkWheelRouting(compact: compact, expanded: expanded, units: .pixel,
                        shiftVertical: vertical, routeRow: true)
                }
            }
        }
    }

    func testHorizontalWheelThroughWindowWithoutShiftAtGapEdges() async throws {
        for compact in [false, true] {
            for expanded in [false, true] {
                for unit: CGScrollEventUnit in [.line, .pixel] {
                    for fraction: CGFloat in [0.08, 0.92] {
                        try await checkWheelRouting(compact: compact, expanded: expanded,
                            units: unit, yFraction: fraction, routeRow: true, routeShift: false)
                    }
                }
            }
        }
    }

    func testShiftConversionPreservesPixelDeltasAndGesturePhases() throws {
        let scroll = WheelSpyScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 2000, height: 200))
        for phase: Int64 in [1, 2, 4] {
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 2, wheel1: -17, wheel2: 0, wheel3: 0))
            cg.flags = .maskShift
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertTrue(ShelfWheelRoutingView.route(event, in: scroll, at: CGPoint(x: 100, y: 100)))
            let delivered = try XCTUnwrap(scroll.lastWheel)
            XCTAssertEqual(delivered.scrollingDeltaX, event.scrollingDeltaY, accuracy: 0.001)
            XCTAssertEqual(delivered.scrollingDeltaY, 0)
            XCTAssertEqual(delivered.phase, event.phase)
            XCTAssertEqual(delivered.hasPreciseScrollingDeltas, event.hasPreciseScrollingDeltas)
            XCTAssertEqual(event.scrollingDeltaY, -17, "The original event must remain intact")
        }
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 2, wheel1: 0, wheel2: -12, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        let momentum = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertTrue(ShelfWheelRoutingView.route(momentum, in: scroll, at: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(scroll.lastWheel === momentum, "Unshifted inertia is forwarded unchanged")
    }

    func testNewCopyAfterSearchResetsRealScrollOffsetAndReopenPreservesManualPosition() async throws {
        for compact in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suite = UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
            let panel = ShelfPanel(contentRect: CGRect(x: 50, y: 50, width: 1120, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            defer { history.stopMonitoring(); panel.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
            for i in 0..<600 { history.add(makeClip("old item \(i)")) }
            history.surface = "shelf"; history.compact = compact; history.query = "old"
            try await Task.sleep(for: .milliseconds(250))
            let host = ShelfHosting.make(history: history)
            panel.contentView = host; host.frame = CGRect(x: 0, y: 0, width: 1120, height: 400)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { descendants($0) } }
            func row() throws -> NSScrollView {
                try XCTUnwrap(descendants(host).compactMap { $0 as? ShelfWheelRoutingView }.first?.enclosingScrollView)
            }
            var scroll = try row()
            scroll.contentView.scroll(to: NSPoint(x: 1500, y: 0)); scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertGreaterThan(scroll.contentView.bounds.minX, 1000)
            let fresh = makeClip("newly copied outside the search")
            panel.orderOut(nil)
            history.add(fresh)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertFalse(history.visible.contains { $0.id == fresh.id })
            history.prepareShelf()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded(); scroll = try row()
            XCTAssertEqual(history.visible.first?.id, fresh.id)
            XCTAssertLessThanOrEqual(scroll.contentView.bounds.minX, 4, "Must align the latest card after the search results update")
            // Recopy the already-selected newest card: its ID does not change.
            scroll.contentView.scroll(to: NSPoint(x: 1000, y: 0)); scroll.reflectScrolledClipView(scroll.contentView)
            history.add(makeClip(fresh.text))
            try await Task.sleep(for: .milliseconds(250))
            scroll = try row()
            XCTAssertLessThanOrEqual(scroll.contentView.bounds.minX, 4)
            history.select(history.visible[8])
            try await Task.sleep(for: .milliseconds(150))
            let remembered = scroll.contentView.bounds.minX
            XCTAssertGreaterThan(remembered, 0)
            history.prepareShelf()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(scroll.contentView.bounds.minX, remembered, accuracy: 1)
            await history.flush()
        }
    }

    private func checkWheelRouting(compact: Bool, expanded: Bool, units: CGScrollEventUnit = .pixel, yFraction: CGFloat = 0.5, shiftVertical: Bool = false, routeRow: Bool = false, routeShift: Bool = true) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "EasyPaste.scroll-routing." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        let layout = ShelfLayout(screenHeight: 900, compact: compact, expanded: expanded)
        let panel = ShelfPanel(contentRect: CGRect(x: 50, y: 50, width: 1120, height: layout.height), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        for i in 0..<15 { history.add(makeClip("https://example.com/link-\(i)")) }
        history.surface = "shelf"; history.shelfScreenHeight = 900; history.compact = compact
        await history.flush()
        for _ in 0..<100 where history.visible.count != 15 { try await Task.sleep(for: .milliseconds(10)) }
        history.shelfPreview = expanded ? history.visible.first : nil
        let host = ShelfHosting.make(history: history)
        panel.contentView = host; host.frame = CGRect(x: 0, y: 0, width: 1120, height: layout.height)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        let scroll = try XCTUnwrap(scrolls.first { ($0.documentView?.frame.width ?? 0) > $0.contentSize.width + 500 })
        if routeRow {
            let bridge = try XCTUnwrap(descendants(host).compactMap { $0 as? ShelfWheelRoutingView }.first)
            XCTAssertTrue(bridge.enclosingScrollView === scroll, "The row bridge must target only the card scroll view")
            XCTAssertTrue(panel.wheelRoutingView === bridge)
            let bridgePoint = bridge.superview!.convert(CGPoint(x: bridge.bounds.midX, y: bridge.bounds.midY), from: bridge)
            XCTAssertTrue(bridge.hitTest(bridgePoint) === bridge, "The native background must receive events in gaps")
            let center = scroll.contentView.convert(CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY), to: nil)
            let outside = scroll.contentView.convert(CGPoint(x: -10, y: -10), to: nil)
            for flags: CGEventFlags in [[], .maskCommand, [.maskShift, .maskCommand], [.maskShift, .maskAlternate], [.maskShift, .maskControl]] {
                let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: -1, wheel2: 0, wheel3: 0))
                cg.flags = flags
                XCTAssertFalse(ShelfWheelRoutingView.route(try XCTUnwrap(NSEvent(cgEvent: cg)), in: scroll, at: center))
            }
            let outsideWheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: -1, wheel2: 0, wheel3: 0))
            outsideWheel.flags = .maskShift
            XCTAssertFalse(ShelfWheelRoutingView.route(try XCTUnwrap(NSEvent(cgEvent: outsideWheel)), in: scroll, at: outside), "Preview and header gestures must not scroll the cards")
        }
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        let cardWidth: CGFloat = compact ? 215 : 252
        let positions = [CGFloat(80), 3 + cardWidth + 6.5, cardWidth + 90, 3 + 2 * cardWidth + 13 + 6.5, 2 * cardWidth + 100]
        let step: Int32 = units == .line ? 1 : 40
        for delta: Int32 in [-step, step] {
          for x in delta < 0 ? positions : Array(positions.reversed()) {
            let point = host.convert(CGPoint(x: x, y: scroll.contentView.bounds.minY + scroll.contentView.bounds.height * yFraction), from: scroll.contentView)
            let hitPoint = host.superview?.convert(point, from: host) ?? point
            let hit = try XCTUnwrap(host.hitTest(hitPoint), "compact=\(compact) expanded=\(expanded) delta=\(delta) x=\(x) offset=\(scroll.contentView.bounds.minX)")
            XCTAssertTrue(hit === scroll || hit.enclosingScrollView === scroll, "Wheel events over the card or its gap must stay in the card scroll view, x=\(x)")
            if positions.first == x {
                XCTAssertFalse(hit is ShelfWheelRoutingView, "The background must not take clicks from card bodies")
            }
            let oldX = scroll.contentView.bounds.minX
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: shiftVertical ? delta : 0, wheel2: shiftVertical ? 0 : delta, wheel3: 0))
            if shiftVertical || (routeRow && routeShift) { cg.flags = .maskShift }
            let windowPoint = host.convert(point, to: nil)
            // Synthetic CGEvents without an associated window expose screen
            // coordinates here. Supply panel-local coordinates to exercise the
            // actual sendEvent path rather than calling the routing helper.
            cg.location = CGPoint(x: windowPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - windowPoint.y)
            let wheel = try XCTUnwrap(NSEvent(cgEvent: cg))
            if routeRow {
                XCTAssertEqual(wheel.locationInWindow.x, windowPoint.x, accuracy: 0.01)
                XCTAssertEqual(wheel.locationInWindow.y, windowPoint.y, accuracy: 0.01)
                panel.sendEvent(wheel)
            } else {
                hit.scrollWheel(with: wheel)
            }
            try await Task.sleep(for: .milliseconds(20))
            if delta < 0 { XCTAssertGreaterThan(scroll.contentView.bounds.minX, oldX, "Wheel events must scroll even over a gap") }
            else { XCTAssertLessThan(scroll.contentView.bounds.minX, oldX, "Reverse wheel events must scroll even over a gap") }
          }
        }
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
        panel.contentView = nil
        XCTAssertNil(panel.wheelRoutingView, "Detaching the row must remove its registration")
    }
}

@MainActor private final class WheelSpyScrollView: NSScrollView {
    var lastWheel: NSEvent?
    override func scrollWheel(with event: NSEvent) { lastWheel = event }
}

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

    private func checkWheelRouting(compact: Bool, expanded: Bool, units: CGScrollEventUnit = .pixel, yFraction: CGFloat = 0.5, shiftVertical: Bool = false, routeRow: Bool = false) async throws {
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
            XCTAssertNil(bridge.hitTest(.zero), "The wheel bridge must not intercept card clicks")
            let center = scroll.contentView.convert(CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY), to: nil)
            let outside = scroll.contentView.convert(CGPoint(x: -10, y: -10), to: nil)
            for flags: CGEventFlags in [[], .maskCommand, [.maskShift, .maskCommand], [.maskShift, .maskAlternate], [.maskShift, .maskControl]] {
                let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: -1, wheel2: 0, wheel3: 0))
                cg.flags = flags
                XCTAssertFalse(ShelfWheelRoutingView.route(try XCTUnwrap(NSEvent(cgEvent: cg)), in: scroll, at: center))
            }
            let precise = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -40, wheel2: 0, wheel3: 0))
            precise.flags = .maskShift
            precise.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            XCTAssertFalse(ShelfWheelRoutingView.route(try XCTUnwrap(NSEvent(cgEvent: precise)), in: scroll, at: center), "Trackpad gestures stay native")
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
            let oldX = scroll.contentView.bounds.minX
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: shiftVertical ? delta : 0, wheel2: shiftVertical ? 0 : delta, wheel3: 0))
            if shiftVertical || routeRow { cg.flags = .maskShift }
            cg.location = panel.convertPoint(toScreen: host.convert(point, to: nil))
            let wheel = try XCTUnwrap(NSEvent(cgEvent: cg))
            if routeRow {
                XCTAssertTrue(ShelfWheelRoutingView.route(wheel, in: scroll, at: host.convert(point, to: nil)))
            } else {
                hit.scrollWheel(with: wheel)
            }
            try await Task.sleep(for: .milliseconds(20))
            if delta < 0 { XCTAssertGreaterThan(scroll.contentView.bounds.minX, oldX, "Wheel events must scroll even over a gap") }
            else { XCTAssertLessThan(scroll.contentView.bounds.minX, oldX, "Reverse wheel events must scroll even over a gap") }
          }
        }
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
    }
}

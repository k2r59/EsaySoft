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

    private func checkWheelRouting(compact: Bool, expanded: Bool) async throws {
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
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        let cardWidth: CGFloat = compact ? 215 : 252
        let positions = [CGFloat(80), 3 + cardWidth + 6.5, cardWidth + 90, 3 + 2 * cardWidth + 13 + 6.5, 2 * cardWidth + 100]
        for delta: Int32 in [-40, 40] {
          for x in delta < 0 ? positions : Array(positions.reversed()) {
            let point = host.convert(CGPoint(x: x, y: scroll.contentView.bounds.midY), from: scroll.contentView)
            let hitPoint = host.superview?.convert(point, from: host) ?? point
            let hit = try XCTUnwrap(host.hitTest(hitPoint), "compact=\(compact) expanded=\(expanded) delta=\(delta) x=\(x) offset=\(scroll.contentView.bounds.minX)")
            XCTAssertTrue(hit === scroll || hit.enclosingScrollView === scroll, "Wheel events over the card or its gap must stay in the card scroll view, x=\(x)")
            let oldX = scroll.contentView.bounds.minX
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: delta, wheel3: 0))
            cg.location = panel.convertPoint(toScreen: host.convert(point, to: nil))
            let wheel = try XCTUnwrap(NSEvent(cgEvent: cg))
            hit.scrollWheel(with: wheel)
            try await Task.sleep(for: .milliseconds(20))
            if delta < 0 { XCTAssertGreaterThan(scroll.contentView.bounds.minX, oldX, "Wheel events must scroll even over a gap") }
            else { XCTAssertLessThan(scroll.contentView.bounds.minX, oldX, "Reverse wheel events must scroll even over a gap") }
          }
        }
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
    }
}

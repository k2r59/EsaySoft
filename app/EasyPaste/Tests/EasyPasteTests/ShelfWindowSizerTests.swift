import AppKit
import XCTest
import CryptoKit
import SwiftUI
@testable import EasyPaste

@MainActor final class ShelfWindowSizerTests: XCTestCase {
    private let collapsed = CGRect(x: 100, y: 112, width: 1120, height: 320)
    private let expanded = CGRect(x: 100, y: 112, width: 1120, height: 920)
    private func panel() -> NSPanel {
        let panel = NSPanel(contentRect: expanded, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        return panel
    }
    func testOpeningReservesSpaceImmediatelyWithTheSameBottomEdge() {
        let panel = panel(); defer { panel.close() }
        panel.setFrame(collapsed, display: false)
        let sizer = ShelfWindowSizer()
        sizer.resize(panel, to: expanded, deferShrink: false)
        XCTAssertEqual(panel.frame, expanded)
        XCTAssertEqual(panel.frame.minY, collapsed.minY)
        sizer.cancel()
    }
    func testCollapseRetainsAnimationSpaceThenReleasesItWithoutMovingTheBottom() async throws {
        let panel = panel(); defer { panel.close() }
        let sizer = ShelfWindowSizer(releaseDelay: .milliseconds(20))
        sizer.resize(panel, to: collapsed, deferShrink: true)
        XCTAssertEqual(panel.frame, expanded)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(panel.frame, collapsed)
        XCTAssertEqual(panel.frame.minY, expanded.minY)
    }
    func testRapidReopeningCancelsAStaleShrink() async throws {
        let panel = panel(); defer { panel.close() }
        let sizer = ShelfWindowSizer(releaseDelay: .milliseconds(20))
        sizer.resize(panel, to: collapsed, deferShrink: true)
        sizer.resize(panel, to: expanded, deferShrink: false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(panel.frame, expanded)
    }
    func testClosingCancelsPendingWindowChanges() async throws {
        let panel = panel(); defer { panel.close() }
        let sizer = ShelfWindowSizer(releaseDelay: .milliseconds(20))
        sizer.resize(panel, to: collapsed, deferShrink: true)
        sizer.cancel()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(panel.frame, expanded)
    }
    func testActualCaptureControlStaysAtTheSameYDuringRapidPreviewChanges() async throws {
        try await checkCaptureControl(compact: false)
    }
    func testCompactCaptureControlStaysCircularAndAnchoredDuringRapidPreviewChanges() async throws {
        try await checkCaptureControl(compact: true)
    }
    func testCaptureControlDoesNotInheritPreviewActionAnimation() async throws {
        try await checkCaptureControl(compact: false, animatedAction: true)
    }
    func testCompactCaptureControlDoesNotInheritPreviewActionAnimation() async throws {
        try await checkCaptureControl(compact: true, animatedAction: true)
    }
    private func checkCaptureControl(compact: Bool, animatedAction: Bool = false) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "EasyPaste.motion-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "monitoring")
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        history.surface = "shelf"; history.shelfScreenHeight = 944; history.compact = compact
        let payload = ClipPayload(representations: [[ClipRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("Essai de mouvement".utf8))]])
        let clip = Clip(title: "Essai", text: "Essai de mouvement", source: "Test", sourceID: "test", kind: .text, fingerprint: Clip.fingerprint(payload), payload: payload)
        history.add(clip); await history.flush()
        let panel = NSPanel(contentRect: collapsed, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let host = ShelfHosting.make(history: history); panel.contentView = host
        if animatedAction { panel.orderFront(nil) }
        let sizer = ShelfWindowSizer()
        history.resizeShelf = { [weak panel, weak history] in
            guard let panel, let history else { return }
            let layout = ShelfLayout(screenHeight: history.shelfScreenHeight, compact: history.compact, expanded: history.shelfPreview != nil, footer: history.shelfNeedsFooter)
            sizer.resize(panel, to: CGRect(x: 100, y: 112, width: 1120, height: layout.height), deferShrink: history.shelfPreview == nil)
        }
        defer {
            history.resizeShelf = nil; sizer.cancel(); panel.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        func control(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.toolTip == "Capture d’écran, texte et vidéo" { return button }
            for child in view.subviews { if let found = control(in: child) { return found } }
            return nil
        }
        for _ in 0..<20 where control(in: host) == nil {
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10))
        }
        let first = try XCTUnwrap(control(in: host))
        if animatedAction {
            first.wantsLayer = true
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertEqual(first.bounds.width, 42, accuracy: 0.5, "The capture control must keep a circular 42-point footprint")
        XCTAssertEqual(first.bounds.height, 42, accuracy: 0.5, "Native button alignment insets must not stretch the circle")
        let baseline = first.convert(first.bounds, to: nil).minY
        func renderedY(_ button: NSButton) -> CGFloat {
            let modelY = button.convert(button.bounds, to: nil).minY
            guard let layer = button.layer, let presentation = layer.presentation() else { return modelY }
            let offset = presentation.convert(layer.bounds, to: nil).minY - layer.convert(layer.bounds, to: nil).minY
            return modelY + (host.isFlipped ? -offset : offset)
        }
        let renderedBaseline = renderedY(first)
        var largestRenderShift: CGFloat = 0
        XCTAssertGreaterThan(baseline, compact ? 150 : 200, "Reject an unlaid-out or zero-coordinate measurement")
        func preview(_ open: Bool) {
            let update = { if open { history.openPreview(clip) } else { history.shelfPreview = nil } }
            if animatedAction { withAnimation(.easeInOut(duration: ShelfLayout.previewAnimationDuration), update) }
            else { update() }
        }
        preview(true)
        for step in 0..<80 {
            if step == 4 { preview(false) }
            if step == 8 { preview(true) }
            if step == 45 { preview(false) }
            host.layoutSubtreeIfNeeded()
            let button = try XCTUnwrap(control(in: host))
            XCTAssertEqual(button.bounds.width, 42, accuracy: 0.5)
            XCTAssertEqual(button.bounds.height, 42, accuracy: 0.5)
            let y = button.convert(button.bounds, to: nil).minY
            XCTAssertEqual(y, baseline, accuracy: 0.5, "The actual shelf control moved at animation sample \(step)")
            largestRenderShift = max(largestRenderShift, abs(renderedY(button) - renderedBaseline))
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(history.shelfPreview)
        XCTAssertLessThanOrEqual(largestRenderShift, 0.5, "The presentation layer moved the shelf even though its layout frame stayed fixed")
        let finalLayout = ShelfLayout(screenHeight: history.shelfScreenHeight, compact: compact, expanded: false, footer: history.shelfNeedsFooter)
        XCTAssertEqual(panel.frame.height, finalLayout.height, accuracy: 0.5, "A completed collapse must release the extra window space")
    }

}

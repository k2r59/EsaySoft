import AppKit
import SwiftUI

/// Registers the whole card viewport with its panel. Wheel delivery no longer
/// depends on SwiftUI's hit target (card, control, or empty spacing).
struct ShelfWheelRouting: NSViewRepresentable {
    func makeNSView(context: Context) -> ShelfWheelRoutingView { ShelfWheelRoutingView() }
    func updateNSView(_ view: ShelfWheelRoutingView, context: Context) { view.register() }
    static func dismantleNSView(_ view: ShelfWheelRoutingView, coordinator: ()) { view.stop() }
}

final class ShelfWheelRoutingView: NSView {
    private weak var registeredPanel: ShelfPanel?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        register()
    }
    func register() {
        guard registeredPanel !== window else { return }
        stop()
        guard let panel = window as? ShelfPanel else { return }
        registeredPanel = panel
        panel.wheelRoutingView = self
    }
    func stop() {
        if registeredPanel?.wheelRoutingView === self { registeredPanel?.wheelRoutingView = nil }
        registeredPanel = nil
    }

    @discardableResult static func route(_ event: NSEvent, in scroll: NSScrollView, at windowPoint: NSPoint) -> Bool {
        guard event.type == .scrollWheel,
              event.modifierFlags.intersection([.control, .option, .command]).isEmpty,
              !scroll.isHiddenOrHasHiddenAncestor,
              let document = scroll.documentView,
              document.bounds.width > scroll.contentView.bounds.width + 0.5 else { return false }
        let point = scroll.contentView.convert(windowPoint, from: nil)
        guard scroll.contentView.visibleRect.contains(point) else { return false }
        // Horizontal wheels and trackpads keep their axes and native inertia.
        // Shift-wheel may arrive on either axis, with line OR pixel deltas.
        let shifted = event.modifierFlags.contains(.shift)
        guard shifted || event.scrollingDeltaX != 0 || !event.momentumPhase.isEmpty || !event.phase.isEmpty else { return false }
        if shifted, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0 {
            guard let cg = event.cgEvent?.copy() else { return false }
            let fields: [(CGEventField, CGEventField)] = [
                (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
                (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
                (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2)
            ]
            // CGEvent setters can update companion delta fields. Snapshot all
            // representations before clearing the vertical axis.
            let values = fields.map { cg.getDoubleValueField($0.0) }
            for (vertical, _) in fields { cg.setDoubleValueField(vertical, value: 0) }
            for (index, pair) in fields.enumerated() {
                cg.setDoubleValueField(pair.1, value: values[index])
            }
            // The axis is now explicit; avoid AppKit applying Shift a second time.
            cg.flags.remove(.maskShift)
            guard let horizontal = NSEvent(cgEvent: cg) else { return false }
            scroll.scrollWheel(with: horizontal)
        } else {
            scroll.scrollWheel(with: event)
        }
        return true
    }
}

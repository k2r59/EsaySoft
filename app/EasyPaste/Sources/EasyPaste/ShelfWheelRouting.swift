import AppKit
import SwiftUI

/// Route a mouse's Shift-wheel at the row level, before SwiftUI chooses a
/// responder for a card or its transparent gap. AppKit still owns the scrolling.
struct ShelfWheelRouting: NSViewRepresentable {
    func makeNSView(context: Context) -> ShelfWheelRoutingView { ShelfWheelRoutingView() }
    func updateNSView(_ view: ShelfWheelRoutingView, context: Context) {}
    static func dismantleNSView(_ view: ShelfWheelRoutingView, coordinator: ()) { view.stop() }
}

final class ShelfWheelRoutingView: NSView {
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  window.attachedSheet == nil, let scroll = self.enclosingScrollView,
                  Self.route(event, in: scroll, at: event.locationInWindow) else { return event }
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    deinit { stop() }

    @discardableResult static func route(_ event: NSEvent, in scroll: NSScrollView, at windowPoint: NSPoint) -> Bool {
        // Preserve trackpad/momentum, ordinary wheel gestures and other modifier
        // combinations. In particular, do not swap axes: macOS may already have.
        guard event.type == .scrollWheel, !event.hasPreciseScrollingDeltas,
              event.modifierFlags.intersection([.shift, .control, .option, .command]) == .shift,
              !scroll.isHiddenOrHasHiddenAncestor,
              let document = scroll.documentView,
              document.bounds.width > scroll.contentView.bounds.width + 0.5 else { return false }
        let point = scroll.contentView.convert(windowPoint, from: nil)
        guard scroll.contentView.visibleRect.contains(point) else { return false }
        scroll.scrollWheel(with: event)
        return true
    }
}

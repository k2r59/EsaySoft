import AppKit
import QuartzCore

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    var pointerMoved: ((NSPoint) -> Void)?
    override func sendEvent(_ event: NSEvent) {
        let pointerEvent = [.mouseMoved, .leftMouseDown, .leftMouseDragged].contains(event.type)
        if pointerEvent { pointerMoved?(convertPoint(toScreen: event.locationInWindow)) }
        super.sendEvent(event)
        // Cursor rectangles in a non-key window can be reset by AppKit while
        // crossing displays. Reassert after dispatch, without a timer or stack.
        if pointerEvent, let view = contentView as? SelectionView, !view.completed {
            SelectionView.captureCursor.set()
        }
    }
}

/// The overlay never draws attributed strings in a mouse-driven draw(_:) loop.
/// AppKit owns the labels; Core Animation updates only the selection border.
final class SelectionView: NSView {
    var instruction = "Glisse pour sélectionner · Échap pour annuler" {
        didSet { instructionLabel.stringValue = instruction; needsLayout = true }
    }
    var done: ((CGRect?) -> Void)?
    var windowFrames: [CGRect] = []
    private var tracking: NSTrackingArea?
    private var cursorTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .enabledDuringMouseDrag, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        // activeAlways deliberately does not support cursorUpdate in AppKit.
        let cursorArea = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .cursorUpdate, .inVisibleRect], owner: self)
        addTrackingArea(cursorArea); cursorTracking = cursorArea
    }
    override func cursorUpdate(with event: NSEvent) { if !completed { Self.captureCursor.set() } }
    override func mouseEntered(with event: NSEvent) { updatePointer(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { coordinatesLabel.isHidden = true }
    override func mouseMoved(with event: NSEvent) {
        updatePointer(at: convert(event.locationInWindow, from: nil))
        guard !windowFrames.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = windowFrames.first { $0.contains(point) }
        border.path = selection.map { CGPath(rect: $0, transform: nil) }
    }
    private var anchor: NSPoint?
    private(set) var selection: CGRect?
    private let border = CAShapeLayer()
    private let dimensionsLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(labelWithString: "")
    private let coordinatesLabel = NSTextField(labelWithString: "")
    private(set) var completed = false
    var pointerCoordinates: String? { coordinatesLabel.isHidden ? nil : coordinatesLabel.stringValue }
    var pointerLabelFrame: CGRect { coordinatesLabel.frame }
    static let captureCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 36, height: 36), flipped: false) { _ in
            let path = NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 16, height: 16))
            path.move(to: NSPoint(x: 18, y: 2)); path.line(to: NSPoint(x: 18, y: 34))
            path.move(to: NSPoint(x: 2, y: 18)); path.line(to: NSPoint(x: 34, y: 18))
            NSColor.white.setStroke(); path.lineWidth = 3; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 1; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 18, y: 18))
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        border.fillColor = nil
        border.strokeColor = NSColor.white.cgColor
        border.lineWidth = 2
        border.actions = ["path": NSNull(), "hidden": NSNull()]
        layer?.addSublayer(border)
        for label in [dimensionsLabel, instructionLabel] {
            label.textColor = .white
            label.isSelectable = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        dimensionsLabel.font = .systemFont(ofSize: 14, weight: .medium)
        dimensionsLabel.isHidden = true
        instructionLabel.font = .systemFont(ofSize: 18, weight: .medium)
        instructionLabel.stringValue = instruction
        coordinatesLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        coordinatesLabel.textColor = .white
        coordinatesLabel.maximumNumberOfLines = 2
        coordinatesLabel.isHidden = true
        coordinatesLabel.wantsLayer = true
        coordinatesLabel.layer?.shadowColor = NSColor.black.cgColor
        coordinatesLabel.layer?.shadowOpacity = 1
        coordinatesLabel.layer?.shadowRadius = 2
        coordinatesLabel.layer?.shadowOffset = .zero
        addSubview(coordinatesLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: Self.captureCursor) }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.frame = bounds
        CATransaction.commit()
        instructionLabel.frame = NSRect(x: 30, y: 30, width: max(0, bounds.width - 60), height: 26)
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(bounds.maxX, max(bounds.minX, point.x)),
                y: min(bounds.maxY, max(bounds.minY, point.y)))
    }

    /// Called for every display, including when a drag is delivered to the
    /// original window after the pointer has already entered another display.
    func updatePointer(at point: NSPoint) {
        guard !completed, bounds.contains(point) else { coordinatesLabel.isHidden = true; return }
        Self.captureCursor.set()
        let text = "\(Int((point.x - bounds.minX).rounded()))\n\(Int((bounds.maxY - point.y).rounded()))"
        if coordinatesLabel.stringValue != text {
            coordinatesLabel.stringValue = text
            coordinatesLabel.sizeToFit()
        }
        let size = coordinatesLabel.frame.size
        let x = point.x + 14 + size.width < bounds.maxX - 4 ? point.x + 14 : point.x - size.width - 14
        let y = point.y - size.height - 10 > bounds.minY + 4 ? point.y - size.height - 10 : point.y + 14
        coordinatesLabel.setFrameOrigin(NSPoint(x: max(bounds.minX + 4, min(x, bounds.maxX - size.width - 4)),
                                                y: max(bounds.minY + 4, min(y, bounds.maxY - size.height - 4))))
        coordinatesLabel.isHidden = false
    }

    func begin(at point: NSPoint) {
        guard !completed else { return }
        updatePointer(at: point)
        anchor = clamped(point)
        update(to: point)
    }

    func update(to point: NSPoint) {
        guard !completed, let anchor else { return }
        updatePointer(at: point)
        let current = clamped(point)
        let rect = CGRect(x: min(anchor.x, current.x), y: min(anchor.y, current.y),
                          width: abs(anchor.x - current.x), height: abs(anchor.y - current.y))
        guard selection != rect else { return }
        selection = rect
        border.path = CGPath(rect: rect, transform: nil)
        let scale = window?.backingScaleFactor ?? 1
        let aligned = (try? CaptureImage.pixelAligned(rect, scale: scale)) ?? rect
        let text = "\(Int((aligned.width * scale).rounded())) × \(Int((aligned.height * scale).rounded())) px"
        if dimensionsLabel.stringValue != text {
            dimensionsLabel.stringValue = text
            dimensionsLabel.sizeToFit()
        }
        dimensionsLabel.isHidden = false
        dimensionsLabel.setFrameOrigin(NSPoint(
            x: min(max(8, rect.minX), max(8, bounds.maxX - dimensionsLabel.frame.width - 8)),
            y: min(rect.maxY + 8, max(0, bounds.maxY - dimensionsLabel.frame.height - 8))))
    }

    func finish(at point: NSPoint) {
        update(to: point)
        complete(selection.flatMap { $0.width > 2 && $0.height > 2 ? $0 : nil })
    }

    func cancel() { complete(nil) }

    private func complete(_ rect: CGRect?) {
        guard !completed else { return }
        completed = true
        coordinatesLabel.isHidden = true
        let callback = done
        done = nil
        callback?(rect)
    }

    override func mouseDown(with event: NSEvent) { if !windowFrames.isEmpty { mouseMoved(with: event); complete(selection); return }; begin(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { update(to: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { finish(at: convert(event.locationInWindow, from: nil)) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { cancel() } }
}

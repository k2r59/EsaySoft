import AppKit
import QuartzCore

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
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
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
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
    private var completed = false

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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
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

    func begin(at point: NSPoint) {
        guard !completed else { return }
        anchor = clamped(point)
        update(to: point)
    }

    func update(to point: NSPoint) {
        guard !completed, let anchor else { return }
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
        let callback = done
        done = nil
        callback?(rect)
    }

    override func mouseDown(with event: NSEvent) { if !windowFrames.isEmpty { mouseMoved(with: event); complete(selection); return }; begin(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { update(to: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { finish(at: convert(event.locationInWindow, from: nil)) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { cancel() } }
}

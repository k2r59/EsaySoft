import Foundation

/// Bound visual work to one display interval. Never queue old pointer samples;
/// the caller reads the current pointer when a frame is allowed. Mouse-up forces
/// a final sample so dropping between two frames still uses the correct zone.
struct DragFrameGate {
    private var lastFrame: TimeInterval?
    mutating func allows(_ time: TimeInterval, interval: TimeInterval, force: Bool = false) -> Bool {
        guard force || lastFrame == nil || time-lastFrame! >= interval else { return false }
        lastFrame = time
        return true
    }
}

/// Read the other application's window only to distinguish a move from a
/// content drag or resize. Once confirmed, hover feedback is entirely local.
struct DragTracking {
    enum Phase { case pending, moving, cancelled }
    let initialPointer: CGPoint
    let initialFrame: CGRect
    private(set) var phase: Phase = .pending

    mutating func update(pointer: CGPoint, readFrame: () -> CGRect?) -> Phase {
        guard phase == .pending else { return phase }
        guard hypot(pointer.x-initialPointer.x, pointer.y-initialPointer.y) > 14 else { return phase }
        guard let actual = readFrame() else { phase = .cancelled; return phase }
        guard abs(actual.width-initialFrame.width) < 3, abs(actual.height-initialFrame.height) < 3 else {
            phase = .cancelled; return phase
        }
        if hypot(actual.minX-initialFrame.minX, actual.minY-initialFrame.minY) > 6 { phase = .moving }
        return phase
    }
}

/// Keep pointer samples cheap, and only repaint when the destination changes.
struct DragHover {
    private(set) var point: CGPoint?
    private(set) var choice: DragChoice?

    mutating func sample(_ newPoint: CGPoint) -> Bool {
        guard newPoint != point else { return false }
        point = newPoint
        return true
    }
    mutating func select(_ newChoice: DragChoice?) -> Bool {
        guard choice != newChoice else { return false }
        choice = newChoice
        return true
    }
}

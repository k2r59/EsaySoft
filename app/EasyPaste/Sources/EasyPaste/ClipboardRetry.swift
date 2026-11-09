import Foundation

/// A promised clipboard payload may appear after its ownership changed. Retry
/// that revision only, with a bounded backoff; never continuously read content.
struct ClipboardRetry {
    private(set) var revision: Int?
    private(set) var attempts = 0
    private var nextAttempt = Date.distantFuture

    func isDue(_ revision: Int, now: Date = Date()) -> Bool {
        self.revision == revision && attempts <= 8 && now >= nextAttempt
    }

    mutating func unavailable(_ revision: Int, now: Date = Date()) {
        if self.revision != revision { self.revision = revision; attempts = 0 }
        attempts += 1
        nextAttempt = attempts <= 8 ? now.addingTimeInterval(min(4, pow(2, Double(attempts - 1)) * 0.65)) : .distantFuture
    }

    mutating func clear() { self = ClipboardRetry() }
}

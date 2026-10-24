import AppKit
import XCTest
@testable import EasyPaste

final class SourceIconCacheTests: XCTestCase {
    @MainActor func testConcurrentCardsShareOneLookupAndBoundedThumbnail() async throws {
        var calls = 0
        let expected = NSImage(size: NSSize(width: 32, height: 32))
        let cache = SourceIconCache { _ in
            calls += 1
            try? await Task.sleep(for: .milliseconds(10))
            return expected
        }
        let results = await withTaskGroup(of: NSImage?.self, returning: [NSImage?].self) { group in
            for _ in 0..<80 { group.addTask { await cache.image(for: "com.apple.finder") } }
            var values: [NSImage?] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.count, 80)
        XCTAssertTrue(results.allSatisfy { $0 === expected })
        XCTAssertEqual(calls, 1)
        for _ in 0..<500 { _ = await cache.image(for: "com.apple.finder") }
        XCTAssertEqual(calls, 1, "Scrolling or selection must not repeat a source lookup")
    }
    @MainActor func testMissingApplicationsAndInvalidSourcesStayCheap() async {
        var calls = 0
        let cache = SourceIconCache { _ in calls += 1; return nil }
        for _ in 0..<50 { _ = await cache.image(for: "app.not-installed.easypaste-test") }
        XCTAssertEqual(calls, 1)
        for id in ["", "demo", "test", "/Applications/Safari.app", "https://example.org", "../com.apple.finder", String(repeating: "a", count: 256) + ".app"] {
            let image = await cache.image(for: id)
            XCTAssertNil(image)
        }
        XCTAssertEqual(calls, 1, "Fallback sources must never reach Launch Services")
    }
    @MainActor func testCancelledCardDoesNotCancelLookupForOtherCards() async {
        var calls = 0
        let expected = NSImage(size: NSSize(width: 32, height: 32))
        let cache = SourceIconCache { _ in
            calls += 1
            try? await Task.sleep(for: .milliseconds(20))
            return expected
        }
        let first = Task { await cache.image(for: "com.apple.finder") }
        await Task.yield()
        first.cancel()
        let next = await cache.image(for: "com.apple.finder")
        XCTAssertTrue(next === expected)
        XCTAssertTrue(cache.cached("com.apple.finder") === expected)
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testInstalledFinderIconIsRasterizedTo64Pixels() async throws {
        let cache = SourceIconCache()
        let loaded = await cache.image(for: "com.apple.finder")
        let image = try XCTUnwrap(loaded)
        XCTAssertEqual(image.size, NSSize(width: 32, height: 32))
        var rect = NSRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 64)
        XCTAssertEqual(cg.height, 64)
    }
}

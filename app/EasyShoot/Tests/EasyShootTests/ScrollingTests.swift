import XCTest
import AppKit
import ScreenCaptureKit
import CoreVideo
@testable import EasyShoot

final class ScrollingTests: XCTestCase {
    private func solid(_ color: NSColor, width: Int = 320, height: Int = 480) -> CGImage {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(color.cgColor); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return c.makeImage()!
    }

    func testRejectsBlackAndTransparentFramesButAcceptsDarkContent() throws {
        XCTAssertThrowsError(try ScrollFrame.validate(solid(.black)))
        XCTAssertThrowsError(try ScrollFrame.validate(solid(.clear)))
        XCTAssertNoThrow(try ScrollFrame.validate(solid(NSColor(white: 0.06, alpha: 1))))
        XCTAssertNoThrow(try ScrollFrame.validate(solid(.white)))
    }

    func testRetinaAssemblyIsPixelExactAcrossFiveScrolls() throws {
        let page = try syntheticPage(width: 960, height: 3400)
        let offsets = [0, 431, 808, 1234, 1621]
        var accumulator = ScrollAccumulator()
        for offset in offsets {
            let image = page.cropping(to: CGRect(x: 0, y: offset, width: 960, height: 960))!
            XCTAssertEqual(try accumulator.append(image).kind, .shifted)
        }
        let result = try ScrollStitcher.assemble(accumulator.strips)
        let expected = page.cropping(to: CGRect(x: 0, y: 0, width: 960, height: 2581))!
        XCTAssertEqual(try ScrollStitcher.Raster(result).pixels, try ScrollStitcher.Raster(expected).pixels)
    }

    func testSmallFramesDoNotTrapOnEmptySearchRange() throws {
        XCTAssertNoThrow(try ScrollStitcher.match(solid(.white, width: 32, height: 32), solid(.red, width: 32, height: 32)))
    }

    func testChangedDimensionsAndMissingOverlapAreRefused() throws {
        XCTAssertThrowsError(try ScrollStitcher.match(solid(.white), solid(.white, width: 321)))
        let page = try syntheticPage(width: 320, height: 2000)
        let a = page.cropping(to: CGRect(x: 0, y: 0, width: 320, height: 480))!
        let b = page.cropping(to: CGRect(x: 0, y: 1400, width: 320, height: 480))!
        XCTAssertEqual(try ScrollStitcher.match(a, b).kind, .unmatched)
    }

    func testStableFrameCheckAndPreviewUseBoundedMemory() throws {
        let page = try syntheticPage(width: 1280, height: 2200)
        let a = page.cropping(to: CGRect(x: 0, y: 0, width: 1280, height: 960))!
        let b = page.cropping(to: CGRect(x: 0, y: 200, width: 1280, height: 960))!
        XCTAssertTrue(try ScrollFrame.isStable(a, a))
        XCTAssertFalse(try ScrollFrame.isStable(a, b))
        let preview = try ScrollFrame.preview(a)
        XCTAssertLessThanOrEqual(preview.width, 620)
        XCTAssertLessThanOrEqual(preview.height, 360)
        XCTAssertLessThan(preview.bytesPerRow * preview.height, 900_000)
        let start = Date()
        for _ in 0..<50 { XCTAssertTrue(try ScrollFrame.isStable(a, a)) }
        print("METRIC: 50 stability checks = \(Date().timeIntervalSince(start)) s")
    }

    func testRetinaConfigurationNeverDownscales() throws {
        let rect = try NativeScreenCapture.pixelAligned(CGRect(x: 10.25, y: 20.75, width: 311.5, height: 223.5), scale: 2)
        XCTAssertEqual(rect, CGRect(x: 10, y: 20.5, width: 312, height: 224))
        let config = try NativeScreenCapture.configuration(size: rect.size, scale: 2)
        XCTAssertEqual(config.width, 624); XCTAssertEqual(config.height, 448)
        XCTAssertFalse(config.scalesToFit)
        XCTAssertEqual(config.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertEqual(config.captureResolution, .best)
    }

    func testInvalidAndExcessiveRegionsAreRejected() throws {
        for rect in [CGRect.zero, CGRect(x: 0, y: 0, width: -5, height: 10),
                     CGRect(x: Double.nan, y: 0, width: 10, height: 10),
                     CGRect(x: 0, y: 0, width: 100_000, height: 100_000)] {
            XCTAssertThrowsError(try NativeScreenCapture.pixelAligned(rect, scale: 2))
        }
    }

    @MainActor func testTransientBlackIsRetriedBeforeFirstAppend() async throws {
        let owner = AppDelegate()
        let session = ScrollingSession(rect: CGRect(x: 0, y: 0, width: 320, height: 480), owner: owner)
        let black = solid(.black), valid = try syntheticPage(width: 320, height: 480)
        var attempts = 0
        session.snapshotProvider = { attempts += 1; return attempts <= 2 ? black : valid }
        await session.sample(force: true)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(session.count, 1); XCTAssertFalse(session.warning)
        session.cancel()
        withExtendedLifetime(owner) {}
    }

    @MainActor func testPersistentBlackPausesWithoutDestroyingValidPortions() async throws {
        let owner = AppDelegate()
        let session = ScrollingSession(rect: CGRect(x: 0, y: 0, width: 320, height: 480), owner: owner)
        let valid = try syntheticPage(width: 320, height: 480)
        session.snapshotProvider = { valid }
        await session.sample(force: true)
        let black = solid(.black)
        var attempts = 0
        session.snapshotProvider = { attempts += 1; return black }
        await session.sample(force: true)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(session.count, 1); XCTAssertEqual(session.height, 480)
        XCTAssertTrue(session.paused); XCTAssertTrue(session.warning)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        session.outputDirectory = directory
        var exported: URL?
        session.completed = { exported = $0 }
        await session.saveValidatedParts()
        let image = try XCTUnwrap(NSImage(contentsOf: XCTUnwrap(exported))?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(try ScrollStitcher.Raster(image).pixels, try ScrollStitcher.Raster(valid).pixels)
        XCTAssertFalse(session.isActive)
        withExtendedLifetime(owner) {}
    }

    @MainActor func testPermissionErrorIsNotRetried() async {
        let owner = AppDelegate()
        let session = ScrollingSession(rect: CGRect(x: 0, y: 0, width: 320, height: 480), owner: owner)
        var attempts = 0
        session.snapshotProvider = { attempts += 1; throw NativeScreenCapture.permissionError() }
        await session.sample()
        XCTAssertEqual(attempts, 1); XCTAssertTrue(session.paused)
        session.cancel()
        withExtendedLifetime(owner) {}
    }

    @MainActor func testCancellationDuringSnapshotCannotAppendOrExport() async throws {
        let owner = AppDelegate()
        let session = ScrollingSession(rect: CGRect(x: 0, y: 0, width: 320, height: 480), owner: owner)
        let valid = try syntheticPage(width: 320, height: 480)
        session.snapshotProvider = {
            try await Task.sleep(for: .milliseconds(40))
            return valid
        }
        let sampling = Task { await session.sample() }
        try await Task.sleep(for: .milliseconds(10))
        session.cancel()
        await sampling.value
        XCTAssertEqual(session.count, 0)
        XCTAssertNil(session.preview); XCTAssertFalse(session.isActive)
        withExtendedLifetime(owner) {}
    }
}

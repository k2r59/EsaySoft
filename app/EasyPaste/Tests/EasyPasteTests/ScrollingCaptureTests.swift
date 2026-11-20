import AppKit
import XCTest
@testable import EasyPaste

final class ScrollingCaptureTests: XCTestCase {
    func testControlsUseTheirLaidOutSizeAndStayOutsideSelectedContent() {
        let displays = [CGRect(x: 0, y: 30, width: 5120, height: 1410),
                        CGRect(x: 5120, y: 0, width: 2560, height: 1440),
                        CGRect(x: -1920, y: -300, width: 1920, height: 1080)]
        for bounds in displays {
            for offset in [CGFloat(20), CGFloat(250), CGFloat(650)] {
                let zone = CGRect(x: bounds.minX + 500, y: bounds.minY + offset, width: 620, height: 670)
                guard bounds.contains(zone) else { continue }
                let panel = ScrollCaptureControlsLayout.frame(zone: zone, bounds: bounds, size: CGSize(width: 410, height: 170))
                XCTAssertTrue(bounds.contains(panel))
                XCTAssertFalse(panel.intersects(zone))
                XCTAssertEqual(panel.width, 410)
            }
        }
    }
    private func document(width: Int = 160, height: Int = 1400) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            // Deterministic textured content, distinct on every vertical row.
            let v = UInt8((y * 53 + x * 13 + (x * y) % 173) % 240)
            bytes[i] = v; bytes[i+1] = UInt8((Int(v) + 41) % 255); bytes[i+2] = UInt8((Int(v) + 97) % 255)
        } }
        let data = Data(bytes)
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func frame(_ image: CGImage, top: Int, height: Int = 360) throws -> CGImage {
        try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: height)))
    }
    private func pixels(_ image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }
    func testFindsExactOverlapsAtSeveralScrollDistances() throws {
        let page = try document()
        let first = try ScrollRaster(frame(page, top: 0))
        for offset in [4, 17, 80, 155, 270] {
            XCTAssertEqual(first.downwardOffset(to: try ScrollRaster(frame(page, top: offset))), offset)
        }
        XCTAssertNil(first.downwardOffset(to: try ScrollRaster(frame(page, top: 500))))
    }
    func testStableFramesAssemblePixelPerfectWithoutDuplicates() async throws {
        let page = try document(), assembler = ScrollAssembler()
        for top in [0, 90, 210, 390] {
            let image = try frame(page, top: top)
            _ = try await assembler.consume(image)
            _ = try await assembler.consume(image)
            _ = try await assembler.consume(image) // No duplicate append when idle.
        }
        let output = try await assembler.finish()
        XCTAssertEqual(output.width, 160); XCTAssertEqual(output.height, 750)
        XCTAssertEqual(try pixels(output), try pixels(frame(page, top: 0, height: 750)))
    }
    func testFirstFrameMustBeStableAndMotionIsNotAppended() async throws {
        let page = try document(), assembler = ScrollAssembler()
        _ = try await assembler.consume(frame(page, top: 0))
        do { _ = try await assembler.finish(); XCTFail("Unstable initial capture must not finish") } catch { }
        _ = try await assembler.consume(frame(page, top: 0))
        for top in [30, 60, 90] { _ = try await assembler.consume(frame(page, top: top)) }
        let output = try await assembler.finish()
        XCTAssertEqual(output.height, 360)
    }
    func testUpwardAndNonOverlappingFramesDoNotCorruptTheResultAndCanRecover() async throws {
        let page = try document(), assembler = ScrollAssembler()
        for top in [100, 200, 100, 800, 300] {
            _ = try await assembler.consume(frame(page, top: top))
            _ = try await assembler.consume(frame(page, top: top))
        }
        let output = try await assembler.finish()
        XCTAssertEqual(output.height, 560)
        XCTAssertEqual(try pixels(output), try pixels(frame(page, top: 100, height: 560)))
    }
    func testMemoryLimitPreservesLastGoodResult() async throws {
        let page = try document(), assembler = ScrollAssembler(pixelLimit: 160 * 400)
        for _ in 0..<2 { _ = try await assembler.consume(frame(page, top: 0)) }
        _ = try await assembler.consume(frame(page, top: 100))
        let result = try await assembler.consume(frame(page, top: 100))
        XCTAssertTrue(result.limitReached)
        let output = try await assembler.finish()
        XCTAssertEqual(output.height, 360)
    }
    func testUniformAndRepeatingFramesAreAmbiguous() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 360, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 160, height: 360))
        let blank = try ScrollRaster(XCTUnwrap(context.makeImage()))
        XCTAssertNil(blank.downwardOffset(to: blank))
        for y in stride(from: 0, to: 360, by: 20) {
            context.setFillColor(NSColor.black.cgColor); context.fill(CGRect(x: 15, y: y, width: 130, height: 8))
        }
        let repeated = try ScrollRaster(XCTUnwrap(context.makeImage()))
        XCTAssertNil(repeated.downwardOffset(to: repeated))
    }
    @MainActor func testTextDocumentOverlapAtRetinaResolution() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1100, height: 2600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 2600))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for i in 0..<55 {
            let text = "Passage \(i * 173) : une capture conserve chaque détail, repère \(i*i+27)."
            (text as NSString).draw(at: NSPoint(x: 30, y: i * 45 + 10), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let page = try XCTUnwrap(context.makeImage())
        let start = try ScrollRaster(frame(page, top: 0, height: 1100))
        XCTAssertEqual(start.downwardOffset(to: try ScrollRaster(frame(page, top: 245, height: 1100))), 245)
    }

    func testVisibleInactiveSourceAndOwnControlsAllowCapture() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 400)
        let source = ScrollCaptureVisibility.Window(id: 1, pid: 10, bounds: CGRect(x: 0, y: 0, width: 800, height: 800))
        let controls = ScrollCaptureVisibility.Window(id: 2, pid: 20, bounds: area)
        let otherScreen = ScrollCaptureVisibility.Window(id: 3, pid: 30, bounds: CGRect(x: 1000, y: 0, width: 800, height: 800))
        XCTAssertTrue(ScrollCaptureVisibility.permits(area: area, source: 1, own: 20, windows: [controls, otherScreen, source]))
    }
    func testTransparentFullscreenDockOverlayDoesNotBlockCapture() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 400)
        let source = ScrollCaptureVisibility.Window(id: 1, pid: 10, bounds: CGRect(x: 0, y: 0, width: 800, height: 800))
        let dock = ScrollCaptureVisibility.Window(id: 2, pid: 30, bounds: CGRect(x: 0, y: 0, width: 5120, height: 1440), desktopOverlay: true)
        XCTAssertTrue(ScrollCaptureVisibility.permits(area: area, source: 1, own: 20, windows: [dock, source]))
    }

    func testOcclusionAndMissingSourcePauseCapture() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 400)
        let source = ScrollCaptureVisibility.Window(id: 1, pid: 10, bounds: CGRect(x: 0, y: 0, width: 800, height: 800))
        let cover = ScrollCaptureVisibility.Window(id: 3, pid: 30, bounds: CGRect(x: 200, y: 200, width: 20, height: 20))
        XCTAssertFalse(ScrollCaptureVisibility.permits(area: area, source: 1, own: 20, windows: [cover, source]))
        XCTAssertFalse(ScrollCaptureVisibility.permits(area: area, source: 1, own: 20, windows: [cover]))
        XCTAssertTrue(ScrollCaptureVisibility.permits(area: area, source: 1, own: 20, windows: [source, cover]))
        let transparent = ScrollCaptureVisibility.Window(id: 4, pid: 30, bounds: area, alpha: 0)
        XCTAssertTrue(ScrollCaptureVisibility.permits(area: area, source: 1, own: 20, windows: [transparent, source]))
    }

    func testCaptureActionRetainsExistingMenuTags() {
        XCTAssertEqual(CaptureAction.area.rawValue, 0)
        XCTAssertEqual(CaptureAction.text.rawValue, 3)
        XCTAssertEqual(CaptureAction.video.rawValue, 4)
        XCTAssertEqual(CaptureAction.scrolling.title, "Capture défilante…")
    }
}

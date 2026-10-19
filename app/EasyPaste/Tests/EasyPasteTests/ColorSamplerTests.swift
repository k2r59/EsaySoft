import XCTest
import AppKit
import SwiftUI
import CryptoKit
@testable import EasyPaste

@MainActor final class ColorSamplerTests: XCTestCase {
    private var history: History!
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-colors-" + UUID().uuidString)
        suite = "EasyPaste.test." + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
        history = History(vault: try ClipVault(directory: folder, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        for _ in 0..<200 { if !history.loading { break }; try await Task.sleep(for: .milliseconds(5)) }
    }
    override func tearDown() async throws {
        history.stopMonitoring(); await history.flush(); history = nil
        defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder)
    }
    func testSRGBConversionAndExactHexRGB() throws {
        let sample = try XCTUnwrap(SampledColor(NSColor(srgbRed: 155.0/255, green: 241.0/255, blue: 203.0/255, alpha: 1)))
        XCTAssertEqual(sample.hex, "#9BF1CB"); XCTAssertEqual(sample.rgb, "rgb(155, 241, 203)")
        XCTAssertEqual(sample.clip.kind, .color); XCTAssertEqual(sample.clip.text, sample.hex)
        XCTAssertEqual(SampledColor(.black)?.hex, "#000000"); XCTAssertEqual(SampledColor(.white)?.hex, "#FFFFFF")
        let wide = try XCTUnwrap(SampledColor(NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)))
        XCTAssertEqual(wide.hex, "#FF0000")
        let gray = try XCTUnwrap(SampledColor(NSColor(white: 0.5, alpha: 1)))
        XCTAssertEqual(gray.red, gray.green); XCTAssertEqual(gray.green, gray.blue)
    }
    func testSamplingAddsDurableColorAndCopiesOnce() async throws {
        let controller = ColorSamplerController(history: history)
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let selected = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
        var result: SampledColor?, wasCopied = false
        controller.presentResult = { result = $0; wasCopied = $1 }
        controller.sample(presenter: { completion in completion(selected); completion(.blue) }, pasteboard: pb)
        for _ in 0..<300 { if !history.samplingColor { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(history.samplingColor); XCTAssertEqual(result?.hex, "#FF8000"); XCTAssertTrue(wasCopied)
        XCTAssertEqual(pb.string(forType: .string), "#FF8000"); XCTAssertEqual(history.clips.count, 1)
        let full = try await history.fullClip(history.clips[0]); XCTAssertEqual(full.text, "#FF8000"); XCTAssertEqual(full.kind, .color)
    }
    func testCancelAndReentryNeverTouchClipboard() async throws {
        let controller = ColorSamplerController(history: history), pb = NSPasteboard(name: .init(UUID().uuidString))
        defer { pb.releaseGlobally() }; pb.setString("préservé", forType: .string)
        var finish: (@MainActor (NSColor?) -> Void)?
        controller.sample(presenter: { finish = $0 }, pasteboard: pb); XCTAssertTrue(history.samplingColor)
        var duplicate = false
        controller.sample(presenter: { _ in duplicate = true }, pasteboard: pb)
        XCTAssertFalse(duplicate); finish?(nil)
        XCTAssertFalse(history.samplingColor); XCTAssertTrue(history.clips.isEmpty)
        XCTAssertEqual(pb.string(forType: .string), "préservé")
    }
    func testBusyCapturePreventsSampler() {
        let controller = ColorSamplerController(history: history)
        history.recording = true
        var called = false
        controller.sample(presenter: { _ in called = true })
        XCTAssertFalse(called); XCTAssertFalse(history.samplingColor)
    }
    func testColorWindowNativeLayoutAndScreenshot() throws {
        let sample = try XCTUnwrap(SampledColor(NSColor(srgbRed: 155.0/255, green: 241.0/255, blue: 203.0/255, alpha: 1)))
        let host = NSHostingView(rootView: ColorSampleView(sample: sample, copied: true, copy: { _ in true }, again: {}, close: {}))
        let size = CGSize(width: 430, height: 550)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.frame = CGRect(origin: .zero, size: size)
        defer { window.close() }; host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 430); XCTAssertLessThanOrEqual(host.fittingSize.height, 550)
        if let directory = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("Pipette-EasyPaste.png"))
        }
    }
}

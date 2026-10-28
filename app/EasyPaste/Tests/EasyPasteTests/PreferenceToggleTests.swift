import AppKit
import SwiftUI
import XCTest
@testable import EasyPaste

@MainActor final class PreferenceToggleTests: XCTestCase {
    func testEnabledSwitchIsColoredAndContainsNoNativeControlThatInterceptsClicks() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for enabled in [false, true] {
                let host = NSHostingView(rootView: PreferenceToggle("Microphone", isOn: .constant(enabled)).padding(20).surface().frame(width: 420))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 76), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = host
                defer { window.close() }
                host.frame = CGRect(x: 0, y: 0, width: 420, height: 76)
                host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(150))
                func views(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(views) }
                XCTAssertFalse(views(host).contains { $0 is NSSwitch }, "The pointer must reach the row button, not a non-interactive AppKit switch")
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if enabled {
                    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(365 * scale), y: Int(38 * scale))?.usingColorSpace(.deviceRGB))
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    XCTAssertGreaterThan(channels.max()! - channels.min()!, 0.15, "On must be colored even in an inactive window")
                }
                if let folder = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
                    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent("switch-\(enabled)-\(appearance.rawValue).png"))
                }
            }
        }
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import EasyTile

@MainActor final class AppearanceTests: XCTestCase {
    func testFreshAndUnknownPreferencesUseLight() {
        withDefaults { defaults in
            XCTAssertEqual(AppAppearance.stored(in: defaults), .light)
            defaults.set("unknown", forKey: AppAppearance.defaultsKey)
            XCTAssertEqual(AppAppearance.stored(in: defaults), .light)
        }
    }

    func testEveryChoiceSurvivesPreferenceReload() {
        withDefaults { defaults in
            for mode in AppAppearance.allCases {
                defaults.set(mode.rawValue, forKey: AppAppearance.defaultsKey)
                XCTAssertEqual(AppAppearance.stored(in: defaults), mode)
            }
        }
    }

    func testAutomaticRemovesTheAppOverrideAndNewWindowsInheritIt() {
        let app = NSApplication.shared, original = NSApplication.shared.appearance
        defer { app.appearance = original }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for mode in [AppAppearance.dark, .light] {
            mode.apply(to: app)
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), mode == .dark ? .darkAqua : .aqua)
        }
        AppAppearance.automatic.apply(to: app)
        XCTAssertNil(app.appearance)
        XCTAssertNil(window.appearance)
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
    }

    func testSemanticColorsMeetTextContrastInBothAppearances() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for background in [Theme.bg, Theme.panel, Theme.raised] {
                for foreground in [Theme.ink, Theme.muted, Theme.warning] + Theme.colors {
                    let ratio = try contrast(foreground, background, appearance)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "Text contrast in \(name.rawValue)")
                }
            }
            XCTAssertGreaterThanOrEqual(try contrast(Theme.onAccent, Theme.mint, appearance), 4.5)
        }
    }

    func testStoredSwiftUIAndAppKitColorsRemainDynamic() throws {
        // These objects are constructed once, as in long-lived editors and panels.
        let background = NSColor(Theme.bg), ink = NSColor(Theme.ink)
        let light = try XCTUnwrap(NSAppearance(named: .aqua)), dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        XCTAssertGreaterThan(try luminance(background, light), 0.8)
        XCTAssertLessThan(try luminance(background, dark), 0.02)
        XCTAssertLessThan(try luminance(ink, light), 0.03)
        XCTAssertGreaterThan(try luminance(ink, dark), 0.8)
    }

    private func contrast(_ foreground: Color, _ background: Color, _ appearance: NSAppearance) throws -> Double {
        let a = try luminance(NSColor(foreground), appearance), b = try luminance(NSColor(background), appearance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    private func luminance(_ color: NSColor, _ appearance: NSAppearance) throws -> Double {
        var rgb: NSColor?
        appearance.performAsCurrentDrawingAppearance { rgb = color.usingColorSpace(.sRGB) }
        let value = try XCTUnwrap(rgb)
        func linear(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return linear(value.redComponent) * 0.2126 + linear(value.greenComponent) * 0.7152 + linear(value.blueComponent) * 0.0722
    }
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "EasyTile.appearance.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}

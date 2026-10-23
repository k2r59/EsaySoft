import AppKit
import SwiftUI
import XCTest
@testable import EasyPaste

final class GlassAppearanceTests: XCTestCase {
    func testUnknownTintFallsBackToOriginalBlue() {
        XCTAssertEqual(GlassTint.resolve("obsolete"), .blue)
        XCTAssertEqual(GlassTint.resolve(""), .blue)
        for tint in GlassTint.allCases {
            XCTAssertEqual(GlassTint.resolve(tint.rawValue), tint)
            XCTAssertEqual(tint.colors.count, 3)
        }
    }
    func testCorruptPreferencesCannotMakeTheFrameInvisible() {
        for value in [Double.nan, .infinity, -.infinity, -20, 0, 0.45, 0.8, 400] {
            let opacity = GlassAppearance.washOpacity(value)
            XCTAssertTrue(opacity.isFinite)
            XCTAssertGreaterThanOrEqual(opacity, 0.199)
            XCTAssertLessThanOrEqual(opacity, 1)
        }
    }

    func testEverySliderStepChangesDarkTransparencyWithoutLosingContrastFloor() {
        for dark in [false, true] {
            var previous = GlassAppearance.washOpacity(0, dark: dark)
            XCTAssertEqual(previous, 1)
            for step in 1...16 {
                let opacity = GlassAppearance.washOpacity(Double(step) * 0.05, dark: dark)
                XCTAssertLessThan(opacity, previous, "Every slider step must visibly change the frame")
                XCTAssertGreaterThanOrEqual(opacity, dark ? 0.86 : 0.199)
                previous = opacity
            }
        }
    }

    @MainActor func testWindowTintKeepsPrimaryAndSecondaryLabelsReadableForEveryPalette() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let canvas = components(Theme.bg)
                for tint in GlassTint.allCases {
                    for value in [0.0, 0.45, 0.8] {
                        let alpha = GlassAppearance.windowTintOpacity(value, dark: name == .darkAqua)
                        for color in tint.colors {
                            let background = zip(components(color), canvas).map { $0 * alpha + $1 * (1 - alpha) }
                            for label in [Theme.ink, Theme.muted] {
                                let a = luminance(components(label)), b = luminance(background)
                                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, "Unreadable window label: \(tint), \(name), \(value)")
                            }
                        }
                    }
                }
            }
        }
        for value in [Double.nan, .infinity, -.infinity, -10, 400] {
            for dark in [false, true] {
                let alpha = GlassAppearance.windowTintOpacity(value, dark: dark)
                XCTAssertTrue(alpha.isFinite)
                XCTAssertTrue((0...1).contains(alpha))
            }
        }
    }

    @MainActor func testControlPlateContrastOverExtremeDesktopColorsInBothThemes() throws {
        // Exercise the actual secondary button plate and opaque card surface.
        // Black/white desktops cover the luminance bounds behind the button.
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let plate = components(GlassAppearance.labelPlate)
                for desktop in [0.0, 1.0] {
                    let background = components(Theme.panel)
                    for text in [Theme.ink, Theme.muted] {
                        let a = luminance(components(text)), b = luminance(background)
                        XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, "Unreadable label in \(name), desktop \(desktop)")
                    }
                    let alpha = name == .darkAqua ? 0.9 : 0.6
                    let button = plate.map { $0 * alpha + desktop * (1 - alpha) }
                    let a = luminance(components(Theme.ink)), b = luminance(button)
                    XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, "Unreadable secondary action")
                    let tab = components(GlassAppearance.selectedTab).map { $0 * 0.94 + desktop * 0.06 }
                    let label = luminance(components(Theme.mint)), tabBackground = luminance(tab)
                    XCTAssertGreaterThanOrEqual((max(label, tabBackground) + 0.05) / (min(label, tabBackground) + 0.05), 4.5, "Unreadable selected tab")
                }
            }
        }
    }
    @MainActor func testDarkFrameProtectsWhiteLabelsAtMaximumTransparency() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        appearance.performAsCurrentDrawingAppearance {
            let alpha = GlassAppearance.washOpacity(0.8, dark: true)
            for color in GlassTint.allCases.flatMap(\.colors) {
                for desktop in [0.0, 1.0] {
                    let background = components(color).map { ($0 * alpha + desktop * (1 - alpha)) * 0.938 + 0.062 }
                    let a = luminance(components(Theme.ink)), b = luminance(background)
                    XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
                }
            }
        }
    }
    private func components(_ color: Color) -> [Double] {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent]
    }
    private func luminance(_ rgb: [Double]) -> Double {
        zip(rgb, [0.2126, 0.7152, 0.0722]).reduce(0) { sum, pair in
            sum + (pair.0 <= 0.04045 ? pair.0 / 12.92 : pow((pair.0 + 0.055) / 1.055, 2.4)) * pair.1
        }
    }
}

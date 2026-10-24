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
            XCTAssertEqual(tint.windowColors.count, 3)
        }
    }
    func testCorruptPreferencesCannotMakeTheFrameInvisible() {
        for value in [Double.nan, .infinity, -.infinity, -20, 0, 0.45, 0.8, 400] {
            for opacity in [GlassAppearance.washOpacity(value), GlassAppearance.materialOpacity(value)] {
                XCTAssertTrue(opacity.isFinite)
                XCTAssertGreaterThanOrEqual(opacity, 0.199)
                XCTAssertLessThanOrEqual(opacity, 1)
            }
        }
    }
    func testEverySliderStepChangesBothLightAndDarkTransparency() {
        for dark in [false, true] {
            var previous = GlassAppearance.washOpacity(0, dark: dark)
            XCTAssertEqual(previous, 1)
            for step in 1...16 {
                let opacity = GlassAppearance.washOpacity(Double(step) * 0.05, dark: dark)
                XCTAssertLessThan(opacity, previous)
                previous = opacity
            }
            XCTAssertEqual(previous, 0.2, accuracy: 0.0001)
        }
        // The library uses one continuous readable coating, not label chips.
        // Even including this coating and the material, the far endpoint must
        // expose the desktop, unlike the opaque zero-transparency endpoint.
        let tint = GlassAppearance.windowTintOpacity(0.8, dark: false)
        let coat = GlassAppearance.windowReadabilityOpacity(0.8)
        let covered = coat + GlassAppearance.materialOpacity(0.8) * (1 - coat)
        let combined = tint + covered * (1 - tint)
        XCTAssertLessThan(combined, 0.9)
        XCTAssertEqual(GlassAppearance.windowTintOpacity(0, dark: false), 1)
    }
    @MainActor func testThemedActionsAndProtectedLabelsMeetContrastOnAnyDesktop() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                for tint in GlassTint.allCases {
                    for action in [tint.accent, tint.accentEnd] {
                        XCTAssertGreaterThanOrEqual(contrast(components(Theme.onAccent), components(action).map { $0 * 0.92 + 0.08 }), 4.5, "Unreadable action: \(tint), \(name)")
                    }
                    for desktop in [0.0, 1.0] {
                        // Actual label plates protect free-standing text; we do
                        // not assume arbitrary desktop content has readable contrast.
                        let sheen = name == .darkAqua ? 0.025 : 0.08
                        let plate = components(tint.controlPlate).map { ($0 * 0.95 + desktop * 0.05) * (1 - sheen) + sheen }
                        for label in [Theme.ink, Theme.muted, tint.accent] {
                            XCTAssertGreaterThanOrEqual(contrast(components(label), plate), 4.5, "Unreadable control: \(tint), \(name), \(desktop)")
                        }
                        for label in [Theme.ink, Theme.muted] {
                            XCTAssertGreaterThanOrEqual(contrast(components(label), components(Theme.panel)), 4.5)
                        }
                    }
                }
            }
        }
    }
    @MainActor func testBorderlessLibraryLabelsRemainReadableAtEveryThemeAndTransparency() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let ink = components(Theme.ink), secondary = components(Theme.chromeSecondary)
                let base = components(Theme.bg)
                for tint in GlassTint.allCases {
                    for step in 0...16 {
                        let amount = Double(step) * 0.05
                        let wash = GlassAppearance.windowTintOpacity(amount, dark: name == .darkAqua)
                        let coat = GlassAppearance.windowReadabilityOpacity(amount)
                        for canvas in tint.windowColors {
                            let rgb = components(canvas)
                            for desktop in [0.0, 1.0] {
                                // Ignore native blur: even the worst unblurred
                                // black/white desktop must not hide these labels.
                                let background = zip(rgb, base).map { color, plate in
                                    color * wash + (plate * coat + desktop * (1 - coat)) * (1 - wash)
                                }
                                for label in [ink, secondary, components(tint.chromeAccent)] {
                                    XCTAssertGreaterThanOrEqual(contrast(label, background), 4.5, "Library label: \(tint), \(name), \(amount), \(desktop)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    @MainActor func testDarkShelfNavigationRemainsReadableOnLightDesktopAtMaximumTransparency() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        appearance.performAsCurrentDrawingAppearance {
            for tint in GlassTint.allCases {
                for step in 0...16 {
                    let amount = Double(step) * 0.05
                    let wash = GlassAppearance.washOpacity(amount, dark: true)
                    let coat = GlassAppearance.windowReadabilityOpacity(amount)
                    for color in tint.colors {
                        let background = zip(components(color), components(Theme.bg)).map { hue, base in
                            // Worst light desktop, plus the top-left 4.2 % sheen.
                            (hue * wash + (base * coat + 1 - coat) * (1 - wash)) * 0.958 + 0.042
                        }
                        XCTAssertGreaterThanOrEqual(contrast(components(Theme.ink), background), 4.5, "Shelf text: \(tint), \(amount)")
                        for mark in tint.markColors {
                            XCTAssertGreaterThanOrEqual(contrast(components(mark), background), 3, "Shelf mark: \(tint), \(amount)")
                        }
                    }
                }
            }
        }
    }
    private func components(_ color: Color) -> [Double] {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent]
    }
    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    private func luminance(_ rgb: [Double]) -> Double {
        zip(rgb, [0.2126, 0.7152, 0.0722]).reduce(0) { sum, pair in
            sum + (pair.0 <= 0.04045 ? pair.0 / 12.92 : pow((pair.0 + 0.055) / 1.055, 2.4)) * pair.1
        }
    }
}

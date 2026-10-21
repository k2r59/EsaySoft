import AppKit
import SwiftUI
import XCTest
@testable import EasyTile

@MainActor final class InterfaceLayoutTests: XCTestCase {
    func testAllPagesAndPalettesFitInBothAppearances() throws {
        let suite = "EasyTile.layout." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TileStore(defaults: defaults), engine = WindowEngine(observeSystem: false)
        let updates = AppUpdates(), login = LoginLaunch(service: FakeLoginItem())
        for page in ["layouts", "shortcuts", "settings"] {
            store.page = page
            try check(MainView(store: store, engine: engine, updates: updates, login: login),
                      size: CGSize(width: 1000, height: 740), name: page)
        }
        try check(LayoutEditor(store: store), size: CGSize(width: 756, height: 560), name: "editor")
        try check(PaletteView(store: store, engine: engine, close: {}), size: CGSize(width: 580, height: 430), name: "palette")
        let state = DragPaletteState(); state.layouts = TileLayout.presets
        try check(DragPaletteView(state: state), size: state.geometry.size, name: "drag-menu")
    }

    func testUserLayoutsAndGapsSurviveReloadWithNewPreferences() throws {
        let suite = "EasyTile.persistence." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TileStore(defaults: defaults)
        store.save("Mon bureau", zones: [TileZone(0, 0, 1, 1, "Travail")])
        store.gap = 18; store.dragEnabled = false
        defaults.set(AppAppearance.dark.rawValue, forKey: AppAppearance.defaultsKey)
        let reloaded = TileStore(defaults: defaults)
        XCTAssertEqual(reloaded.customLayouts.count, 1)
        XCTAssertEqual(reloaded.customLayouts.first?.name, "Mon bureau")
        XCTAssertEqual(reloaded.gap, 18); XCTAssertFalse(reloaded.dragEnabled)
        XCTAssertEqual(AppAppearance.stored(in: defaults), .dark)
    }

    private func check<V: View>(_ view: V, size: CGSize, name: String) throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = host
            defer { window.close() }
            host.frame = CGRect(origin: .zero, size: size); host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, size.width, name)
            if let folder = ProcessInfo.processInfo.environment["EASYTILE_LAYOUT_SNAPSHOTS"] {
                let url = URL(fileURLWithPath: folder)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(name + "-" + appearance.rawValue + ".png"))
            }
        }
    }
}

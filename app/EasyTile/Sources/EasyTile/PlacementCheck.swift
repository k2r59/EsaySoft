import AppKit

// Explicit development check. Only touches the disposable TileFixture app.
@MainActor
enum PlacementCheck {
    static func run() async {
        let engine = WindowEngine()
        guard engine.trusted else { print("BLOCKED: Accessibility is not authorized"); return }
        engine.refresh()
        guard let win = engine.windows.first(where: { $0.app.bundleIdentifier == "app.easytile.fixture" }), let original = engine.frame(win.element) else { print("BLOCKED: Start TileFixture first"); return }
        engine.selectedID = win.id; engine.followSelectedScreen()
        let initialScreen = engine.screenIndex
        var failures = 0
        func check(_ name: String, _ expected: CGRect) {
            guard let actual = engine.frame(win.element) else { failures += 1; print("FAIL: \(name) unreadable"); return }
            let differences = [actual.minX-expected.minX,actual.minY-expected.minY,actual.width-expected.width,actual.height-expected.height]
            if differences.allSatisfy({ abs($0) < 4 }) { print("PASS: \(name)") }
            else { failures += 1; print("FAIL: \(name), expected \(expected), actual \(actual)") }
        }
        let zone = TileLayout.presets[0].zones[0]
        let expected = TileGeometry.frame(zone:zone,visible:TileGeometry.accessibilityRect(engine.screen!.visibleFrame,primaryTop:engine.primaryTop),gap:12)
        engine.apply(zone,gap:12)
        try? await Task.sleep(for:.milliseconds(350))
        check("Half-screen placement",expected)
        engine.undo()
        try? await Task.sleep(for:.milliseconds(350))
        check("Undo restores original frame",original)
        if engine.screens.count > 1 {
            engine.nextScreen()
            try? await Task.sleep(for:.milliseconds(350))
            if let actual = engine.frame(win.element), let screen = engine.screen, TileGeometry.accessibilityRect(screen.visibleFrame,primaryTop:engine.primaryTop).contains(CGPoint(x:actual.midX,y:actual.midY)) { print("PASS: Move to another screen") } else { failures += 1; print("FAIL: Move to another screen") }
            engine.undo()
            try? await Task.sleep(for:.milliseconds(350))
            check("Undo across screens",original)
        }
        engine.screenIndex = initialScreen
        // Restore even if a check failed.
        engine.move(win,to:original,remember:false)
        try? await Task.sleep(for:.milliseconds(350))
        print("Placement verification: \(failures) failure(s)")
    }
}

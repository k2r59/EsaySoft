import AppKit
import QuartzCore
import XCTest
@testable import EasyTile

@MainActor final class DragRenderingTests: XCTestCase {
    private let layouts = TileLayout.presets
    private let geometry = DragPaletteGeometry(columns:8,count:8)

    func testSweepingAllModelsReusesLayersAndOnlyHighlightsLatestZone() throws {
        let view = NativeDragPaletteView()
        view.configure(layouts:layouts,geometry:geometry)
        view.frame = CGRect(origin:.zero,size:geometry.size); view.layoutSubtreeIfNeeded()
        let identities = view.zoneLayers.mapValues(ObjectIdentifier.init)
        let subviewCount = view.subviews.count
        var times: [Double] = []
        for _ in 0..<100 {
            for (i,layout) in layouts.enumerated() {
                for (j,_) in layout.zones.enumerated() {
                    let choice = DragChoice(layoutIndex:i,zoneIndex:j)
                    let start = ProcessInfo.processInfo.systemUptime
                    view.select(choice); CATransaction.flush()
                    times.append(ProcessInfo.processInfo.systemUptime-start)
                    XCTAssertEqual(view.choice,choice)
                    XCTAssertEqual(view.zoneLayers.values.filter { $0.lineWidth == 2 }.count,1)
                    XCTAssertEqual(view.zoneLayers[choice]?.lineWidth,2)
                }
                view.select(nil) // Crossing a gap must clear the old highlight.
                XCTAssertTrue(view.zoneLayers.values.allSatisfy { $0.lineWidth == 1 })
            }
        }
        XCTAssertEqual(view.zoneLayers.mapValues(ObjectIdentifier.init),identities)
        XCTAssertEqual(view.subviews.count,subviewCount)
        XCTAssertTrue(view.zoneLayers.values.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        times.sort()
        print("DRAG_RENDER_MUTATIONS \(times.count) transitions; p95 \(times[Int(Double(times.count)*0.95)]*1000)ms; max \(times.last!*1000)ms (AppKit/layer commits, excludes display latency)")
    }

    func testReconfigurationDoesNotLeaveHiddenModelsOrAnOldHighlight() {
        let view = NativeDragPaletteView()
        view.configure(layouts:layouts,geometry:geometry)
        view.select(DragChoice(layoutIndex:7,zoneIndex:0))
        let smaller = DragPaletteGeometry(columns:2,count:2)
        view.configure(layouts:layouts,geometry:smaller)
        XCTAssertNil(view.choice)
        XCTAssertEqual(view.zoneLayers.count,layouts.prefix(2).reduce(0) { $0+$1.zones.count })
        view.select(DragChoice(layoutIndex:7,zoneIndex:0))
        XCTAssertNil(view.choice)
        let point = smaller.zoneFrame(layoutIndex:1,zone:layouts[1].zones[0])
        view.select(smaller.hit(CGPoint(x:point.midX,y:point.midY),layouts:layouts))
        XCTAssertEqual(view.choice,DragChoice(layoutIndex:1,zoneIndex:0))
    }

    func testPreviewKeepsOneSurfaceAcrossEveryZoneAndConvertsOtherScreens() throws {
        let preview = DragPreviewController()
        defer { preview.close() }
        let screens = [CGRect(x:0,y:0,width:5120,height:1415), CGRect(x:-2560,y:30,width:2560,height:1415), CGRect(x:100,y:1440,width:1920,height:1080)]
        var identity: ObjectIdentifier?
        for screen in screens {
            for _ in 0..<30 {
                for layout in layouts {
                    for zone in layout.zones {
                        let target = CGRect(x:screen.minX+zone.x*screen.width,y:screen.maxY-(zone.y+zone.height)*screen.height,width:zone.width*screen.width,height:zone.height*screen.height).insetBy(dx:8,dy:8)
                        preview.show(target:target,screen:screen,orderFront:false)
                        let panel = try XCTUnwrap(preview.panel)
                        if let identity { XCTAssertEqual(ObjectIdentifier(panel),identity) }
                        else { identity = ObjectIdentifier(panel) }
                        XCTAssertEqual(panel.frame,screen)
                        XCTAssertEqual(preview.view.target,target.offsetBy(dx:-screen.minX,dy:-screen.minY))
                        XCTAssertFalse(preview.view.shape.isHidden)
                        XCTAssertEqual(preview.view.shape.path?.boundingBoxOfPath,preview.view.target?.insetBy(dx:3.5,dy:3.5))
                        XCTAssertTrue((preview.view.shape.animationKeys() ?? []).isEmpty)
                    }
                    preview.hideTarget()
                    XCTAssertTrue(preview.view.shape.isHidden)
                    XCTAssertEqual(preview.panel?.frame,screen)
                }
            }
        }
        preview.close()
        XCTAssertNil(preview.view.target)
        XCTAssertFalse(try XCTUnwrap(preview.panel).isVisible)
    }

    func testNativePaletteAndPreviewRenderInBothAppearances() throws {
        for name in [NSAppearance.Name.aqua,.darkAqua] {
            let palette = NativeDragPaletteView()
            palette.configure(layouts:layouts,geometry:geometry)
            palette.select(DragChoice(layoutIndex:2,zoneIndex:1))
            try snapshot(palette,size:geometry.size,name:"native-palette-"+name.rawValue,appearance:name)
            let preview = DragPreviewView()
            preview.show(CGRect(x:60,y:40,width:400,height:250))
            try snapshot(preview,size:CGSize(width:640,height:400),name:"native-preview-"+name.rawValue,appearance:name)
            XCTAssertEqual(try XCTUnwrap(preview.shape.fillColor).alpha,0.13,accuracy:0.001)
            XCTAssertEqual(try XCTUnwrap(preview.shape.strokeColor).alpha,0.85,accuracy:0.001)
            XCTAssertNotNil(preview.shape.path)
            XCTAssertEqual(preview.shape.frame,preview.bounds)
        }
    }

    private func snapshot(_ view:NSView,size:CGSize,name:String,appearance:NSAppearance.Name) throws {
        let window = NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.appearance = NSAppearance(named:appearance); window.contentView = view
        defer { window.close() }
        view.frame = CGRect(origin:.zero,size:size); view.layoutSubtreeIfNeeded(); CATransaction.flush()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds))
        view.cacheDisplay(in:view.bounds,to:bitmap)
        let data = try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        XCTAssertGreaterThan(data.count,1000)
        if let folder = ProcessInfo.processInfo.environment["EASYTILE_LAYOUT_SNAPSHOTS"] {
            let url = URL(fileURLWithPath:folder)
            try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
            try data.write(to:url.appendingPathComponent(name+".png"))
        }
    }
}

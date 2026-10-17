import XCTest
@testable import EasyTile

final class GeometryTests: XCTestCase {
    func testAllPresetZonesAreInsideUnitScreenAndDoNotOverlap() {
        for layout in TileLayout.presets {
            XCTAssertEqual(layout.zones.reduce(0) { $0 + $1.width*$1.height },1,accuracy:0.00001,layout.name)
            for (i,z) in layout.zones.enumerated() {
                XCTAssertTrue(z.isValid,layout.name)
                for other in layout.zones.dropFirst(i+1) {
                    let overlap = z.rect.intersection(other.rect)
                    XCTAssertTrue(overlap.isNull || overlap.width < 0.00001 || overlap.height < 0.00001,layout.name)
                }
            }
        }
    }
    func testDuoHasEqualOuterAndInnerGaps() {
        let screen = CGRect(x:0,y:25,width:1440,height:850)
        let left = TileGeometry.frame(zone:TileLayout.presets[0].zones[0],visible:screen,gap:12)
        let right = TileGeometry.frame(zone:TileLayout.presets[0].zones[1],visible:screen,gap:12)
        XCTAssertEqual(left.minX,12); XCTAssertEqual(right.minX-left.maxX,12)
        XCTAssertEqual(screen.maxX-right.maxX,12); XCTAssertEqual(left.minY-screen.minY,12)
        XCTAssertEqual(left.width,right.width)
    }
    func testCoordinateConversionForScreensAboveAndLeftOfPrimary() {
        let left = TileGeometry.accessibilityRect(CGRect(x:-1920,y:0,width:1920,height:1080),primaryTop:900)
        XCTAssertEqual(left,CGRect(x:-1920,y:-180,width:1920,height:1080))
        let above = TileGeometry.accessibilityRect(CGRect(x:0,y:900,width:1440,height:900),primaryTop:900)
        XCTAssertEqual(above.minY,-900)
    }
    func testZonesRemainInsideNegativeOriginScreen() {
        let screen = CGRect(x:-2560,y:-1400,width:2560,height:1360)
        for layout in TileLayout.presets { for zone in layout.zones {
            let f = TileGeometry.frame(zone:zone,visible:screen,gap:24)
            XCTAssertTrue(screen.contains(f),layout.name)
            XCTAssertGreaterThan(f.width,0); XCTAssertGreaterThan(f.height,0)
        } }
    }
    func testInvalidAndNonFiniteCustomZonesRejected() {
        XCTAssertFalse(TileZone(-0.1,0,1,1,"").isValid)
        XCTAssertFalse(TileZone(0,0,0,1,"").isValid)
        XCTAssertFalse(TileZone(0.5,0,0.6,1,"").isValid)
        XCTAssertFalse(TileZone(.nan,0,1,1,"").isValid)
        XCTAssertFalse(TileZone(0,0,.infinity,1,"").isValid)
    }
    func testGapClampedOnTinyScreens() {
        let f = TileGeometry.frame(zone:TileZone(0,0,1,1,""),visible:CGRect(x:0,y:0,width:100,height:80),gap:1000)
        XCTAssertEqual(f,CGRect(x:8,y:8,width:84,height:64))
    }
    func testDragPaletteHitsOnlyVisibleZones() {
        let g = DragPaletteGeometry(columns:4,count:8)
        XCTAssertEqual(g.rows,2)
        for (i,l) in TileLayout.presets.enumerated() { for (j,z) in l.zones.enumerated() {
            let r = g.zoneFrame(layoutIndex:i,zone:z)
            XCTAssertEqual(g.hit(CGPoint(x:r.midX,y:r.midY),layouts:TileLayout.presets),DragChoice(layoutIndex:i,zoneIndex:j))
        } }
        XCTAssertNil(g.hit(CGPoint(x:10,y:20),layouts:TileLayout.presets))
        XCTAssertNil(g.hit(CGPoint(x:18,y:130),layouts:TileLayout.presets))
        XCTAssertNil(g.hit(CGPoint(x:900,y:80),layouts:TileLayout.presets))
    }
    func testDragPaletteDoesNotTargetHiddenLayouts() {
        let g = DragPaletteGeometry(columns:2,count:2)
        let r = g.zoneFrame(layoutIndex:2,zone:TileLayout.presets[2].zones[0])
        XCTAssertNil(g.hit(CGPoint(x:r.midX,y:r.midY),layouts:TileLayout.presets))
    }

}

import AppKit
import SwiftUI

struct DragChoice: Hashable {
    let layoutIndex: Int
    let zoneIndex: Int
}
struct DragPaletteGeometry {
    let columns: Int
    let count: Int
    var rows: Int { (count + columns - 1) / columns }
    var size: CGSize { CGSize(width: Double(columns)*100+32, height: 57+Double(rows)*95+16) }
    func card(_ index: Int) -> CGRect { CGRect(x:16+Double(index%columns)*100,y:57+Double(index/columns)*95,width:90,height:80) }
    func zoneFrame(layoutIndex: Int, zone: TileZone) -> CGRect {
        let c = card(layoutIndex)
        return CGRect(x:c.minX+6+zone.x*78+2,y:c.minY+6+zone.y*48+2,width:max(1,zone.width*78-4),height:max(1,zone.height*48-4))
    }
    func hit(_ point: CGPoint, layouts: [TileLayout]) -> DragChoice? {
        for (i,layout) in layouts.prefix(count).enumerated() {
            for (j,zone) in layout.zones.enumerated() where zoneFrame(layoutIndex:i,zone:zone).contains(point) { return DragChoice(layoutIndex:i,zoneIndex:j) }
        }
        return nil
    }
}
@MainActor
final class DragPaletteState {
    var choice: DragChoice?
    var layouts: [TileLayout] = []
    var geometry = DragPaletteGeometry(columns:8,count:8)
}
/// SwiftUI adapter for previews and layout checks. Live dragging updates the
/// native view directly, without invalidating an entire SwiftUI view hierarchy.
struct DragPaletteView: NSViewRepresentable {
    let state: DragPaletteState
    func makeNSView(context: Context) -> NativeDragPaletteView { NativeDragPaletteView() }
    func updateNSView(_ view: NativeDragPaletteView, context: Context) {
        view.configure(layouts:state.layouts,geometry:state.geometry)
        view.select(state.choice)
    }
}

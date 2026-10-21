import AppKit
import SwiftUI

struct DragChoice: Equatable {
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
final class DragPaletteState: ObservableObject {
    @Published var choice: DragChoice?
    @Published var layouts: [TileLayout] = []
    var geometry = DragPaletteGeometry(columns:8,count:8)
}
struct DragPaletteView: View {
    @ObservedObject var state: DragPaletteState
    var body: some View {
        ZStack(alignment:.topLeading) {
            RoundedRectangle(cornerRadius:18).fill(Theme.panel.opacity(0.98)).overlay(RoundedRectangle(cornerRadius:18).strokeBorder(Theme.ink.opacity(0.17)))
            HStack(spacing:9) {
                Image(systemName:"rectangle.3.group.fill").foregroundStyle(Theme.mint)
                Text(state.choice == nil ? "Où veux-tu placer cette fenêtre ?" : "Relâche pour placer la fenêtre").font(.system(size:12,weight:.semibold))
                Spacer()
                Text("ÉCHAP POUR ANNULER").font(.system(size:8,weight:.medium)).tracking(0.7).foregroundStyle(Theme.muted)
            }.padding(.horizontal,19).frame(height:48)
            ForEach(Array(state.layouts.prefix(state.geometry.count).enumerated()),id:\.element.id) { index,layout in
                let card = state.geometry.card(index)
                ZStack(alignment:.topLeading) {
                    RoundedRectangle(cornerRadius:10).fill(Theme.bg.opacity(0.8))
                    ForEach(Array(layout.zones.enumerated()),id:\.element.id) { j,z in
                        let r = state.geometry.zoneFrame(layoutIndex:index,zone:z)
                        let active = state.choice == DragChoice(layoutIndex:index,zoneIndex:j)
                        let color = Theme.colors[j % 4]
                        RoundedRectangle(cornerRadius:3).fill(color.opacity(active ? 0.85 : 0.16))
                            .overlay(RoundedRectangle(cornerRadius:3).strokeBorder(color.opacity(active ? 1 : 0.3),lineWidth:active ? 2 : 1))
                            .frame(width:r.width,height:r.height).offset(x:r.minX-card.minX,y:r.minY-card.minY)
                    }
                    Text(layout.name).font(.system(size:9,weight:.medium)).foregroundStyle(state.choice?.layoutIndex == index ? Theme.mint : Theme.muted).lineLimit(1).frame(width:82).offset(x:4,y:62)
                }.frame(width:card.width,height:card.height).offset(x:card.minX,y:card.minY)
            }
        }.frame(width:state.geometry.size.width,height:state.geometry.size.height).foregroundStyle(Theme.ink)
    }
}

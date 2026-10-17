import SwiftUI

struct LayoutEditor: View {
    @ObservedObject var store: TileStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Mon espace"
    @State private var zones: [TileZone] = []
    @State private var start: CGPoint?
    @State private var end: CGPoint?
    @State private var hint = "Dessine une zone, puis une autre. Jusqu’à 9 zones, sans chevauchement."
    private let cols = 12
    private let rows = 8
    private func zone(from a: CGPoint, to b: CGPoint, size: CGSize) -> TileZone {
        let x1 = max(0,min(cols-1,Int(a.x / size.width * Double(cols))))
        let y1 = max(0,min(rows-1,Int(a.y / size.height * Double(rows))))
        let x2 = max(0,min(cols-1,Int(b.x / size.width * Double(cols))))
        let y2 = max(0,min(rows-1,Int(b.y / size.height * Double(rows))))
        return TileZone(Double(min(x1,x2))/Double(cols),Double(min(y1,y2))/Double(rows),Double(abs(x2-x1)+1)/Double(cols),Double(abs(y2-y1)+1)/Double(rows),"Zone \(zones.count+1)")
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 22) {
            HStack { VStack(alignment: .leading,spacing: 7) { Text("Un espace qui te ressemble.").font(.system(size: 25,weight: .semibold)).tracking(-0.7); Text("Glisse sur la grille pour dessiner tes zones.").font(.system(size: 12)).foregroundStyle(Theme.muted) }; Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(TileButtonStyle()).accessibilityLabel("Fermer l’éditeur") }
            HStack { Text("Nom").foregroundStyle(Theme.muted); TextField("Nom de la disposition",text: $name).textFieldStyle(.roundedBorder).onChange(of: name) { _,value in if value.count > 40 { name = String(value.prefix(40)) } }; Spacer(); Text("GRILLE 12 × 8").font(.system(size: 9,weight: .semibold)).tracking(1.4).foregroundStyle(Theme.muted) }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.bg)
                    Path { p in
                        for c in 0...cols { let x = geo.size.width * Double(c)/Double(cols); p.move(to: CGPoint(x:x,y:0)); p.addLine(to: CGPoint(x:x,y:geo.size.height)) }
                        for r in 0...rows { let y = geo.size.height * Double(r)/Double(rows); p.move(to: CGPoint(x:0,y:y)); p.addLine(to: CGPoint(x:geo.size.width,y:y)) }
                    }.stroke(.white.opacity(0.09),lineWidth: 1)
                    ForEach(Array(zones.enumerated()),id: \.element.id) { index,z in zoneView(z, color: Theme.colors[index%4], size: geo.size) }
                    if let start, let end { zoneView(zone(from:start,to:end,size:geo.size),color: Theme.mint,size:geo.size).opacity(0.7) }
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { v in if start == nil { start = v.startLocation }; end = v.location }.onEnded { v in
                    defer { start = nil; end = nil }
                    guard zones.count < 9 else { hint = "9 zones maximum. Retire une zone pour continuer."; return }
                    let z = zone(from: start ?? v.startLocation,to:v.location,size:geo.size)
                    guard !zones.contains(where: { $0.rect.intersection(z.rect).width > 0.0001 && $0.rect.intersection(z.rect).height > 0.0001 }) else { hint = "Les zones ne doivent pas se chevaucher."; return }
                    zones.append(z); hint = "\(zones.count) zone\(zones.count > 1 ? "s" : "") · Tu peux continuer à dessiner."
                }).clipShape(RoundedRectangle(cornerRadius:12))
            }.frame(height: 300).accessibilityLabel("Grille de création, 12 colonnes et 8 lignes. Dessiner avec la souris.")
            Text(hint).font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack { Button("Retirer la dernière zone") { if !zones.isEmpty { zones.removeLast() } }.buttonStyle(TileButtonStyle()).disabled(zones.isEmpty); Spacer(); Button("Annuler") { dismiss() }.buttonStyle(TileButtonStyle()); Button("Enregistrer la disposition") { store.save(name,zones:zones); dismiss() }.buttonStyle(TileButtonStyle(primary:true)).disabled(zones.isEmpty) }
        }.padding(28).frame(width: 700).background(Theme.panel).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
    private func zoneView(_ z: TileZone,color:Color,size:CGSize) -> some View {
        RoundedRectangle(cornerRadius:7).fill(color.opacity(0.2)).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(color.opacity(0.7))).overlay(Text(z.label).font(.system(size:11,weight:.semibold)).foregroundStyle(color)).frame(width:max(1,size.width*z.width-6),height:max(1,size.height*z.height-6)).offset(x:size.width*z.x+3,y:size.height*z.y+3)
    }
}

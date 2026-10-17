import AppKit

struct TileZone: Codable, Identifiable, Equatable {
    var id = UUID()
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var label: String
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    init(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ label: String) {
        self.x = x; self.y = y; width = w; height = h; self.label = label
    }
    var isValid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.00001 && y + height <= 1.00001 }
}
struct TileLayout: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var symbol: String
    var zones: [TileZone]
    var custom = false
    static let presets: [TileLayout] = [
        .init(id: "duo", name: "Duo", subtitle: "Deux espaces, un équilibre.", symbol: "rectangle.split.2x1", zones: [.init(0,0,0.5,1,"Gauche"), .init(0.5,0,0.5,1,"Droite")]),
        .init(id: "focus", name: "Focus", subtitle: "La place pour l’essentiel.", symbol: "rectangle.leadinghalf.inset.filled", zones: [.init(0,0,2.0/3,1,"Principal"),.init(2.0/3,0,1.0/3,1,"Référence")]),
        .init(id: "trio", name: "Trio", subtitle: "Tout sous les yeux.", symbol: "rectangle.split.3x1", zones: [.init(0,0,1.0/3,1,"Gauche"),.init(1.0/3,0,1.0/3,1,"Centre"),.init(2.0/3,0,1.0/3,1,"Droite")]),
        .init(id: "studio", name: "Studio", subtitle: "Créer, comparer, échanger.", symbol: "rectangle.split.2x2", zones: [.init(0,0,2.0/3,1,"Principal"),.init(2.0/3,0,1.0/3,0.5,"En haut"),.init(2.0/3,0.5,1.0/3,0.5,"En bas")]),
        .init(id: "quad", name: "Quatuor", subtitle: "Quatre fenêtres, zéro désordre.", symbol: "square.grid.2x2", zones: [.init(0,0,0.5,0.5,"Haut gauche"),.init(0.5,0,0.5,0.5,"Haut droite"),.init(0,0.5,0.5,0.5,"Bas gauche"),.init(0.5,0.5,0.5,0.5,"Bas droite")]),
        .init(id: "stack", name: "Superposé", subtitle: "Une autre façon de partager.", symbol: "rectangle.split.1x2", zones: [.init(0,0,1,0.5,"En haut"),.init(0,0.5,1,0.5,"En bas")]),
        .init(id: "wide", name: "Grand angle", subtitle: "Un centre et deux repères.", symbol: "rectangle.center.inset.filled", zones: [.init(0,0,0.25,1,"Gauche"),.init(0.25,0,0.5,1,"Centre"),.init(0.75,0,0.25,1,"Droite")]),
        .init(id: "full", name: "Plein espace", subtitle: "Toute la place, Dock préservé.", symbol: "arrow.up.left.and.arrow.down.right", zones: [.init(0,0,1,1,"Agrandir")])
    ]
}
enum TileGeometry {
    // Both inputs and outputs use Accessibility's top-left coordinate system.
    static func frame(zone: TileZone, visible: CGRect, gap: Double) -> CGRect {
        let g = min(max(gap, 0), min(visible.width, visible.height) / 10)
        let raw = CGRect(x: visible.minX + zone.x * visible.width, y: visible.minY + zone.y * visible.height, width: zone.width * visible.width, height: zone.height * visible.height)
        let left = zone.x < 0.00001 ? g : g/2
        let top = zone.y < 0.00001 ? g : g/2
        let right = zone.x + zone.width > 0.99999 ? g : g/2
        let bottom = zone.y + zone.height > 0.99999 ? g : g/2
        return CGRect(x: raw.minX + left, y: raw.minY + top, width: max(1, raw.width-left-right), height: max(1, raw.height-top-bottom)).integral
    }
    static func accessibilityRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

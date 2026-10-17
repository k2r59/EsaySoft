import AppKit
import SwiftUI

@MainActor
final class TileStore: ObservableObject {
    @Published var selectedLayoutID = "duo"
    @Published var page = "layouts"
    @Published var gap: Double { didSet { UserDefaults.standard.set(gap, forKey: "gap") } }
    @Published var customLayouts: [TileLayout] = []
    @Published var dragEnabled: Bool { didSet { UserDefaults.standard.set(dragEnabled, forKey: "dragEnabled") } }
    @Published var showEditor = false
    var showPalette: (() -> Void)?
    var layouts: [TileLayout] { TileLayout.presets + customLayouts }
    var layout: TileLayout { layouts.first { $0.id == selectedLayoutID } ?? layouts[0] }
    init() {
        gap = UserDefaults.standard.object(forKey: "gap") == nil ? 12 : min(max(UserDefaults.standard.double(forKey: "gap"),0),32)
        // Enable the new automatic menu once, including upgrades from the old Option-only mode.
        if !UserDefaults.standard.bool(forKey: "automaticDragMenuMigrated") {
            UserDefaults.standard.set(true, forKey: "dragEnabled")
            UserDefaults.standard.set(true, forKey: "automaticDragMenuMigrated")
        }
        dragEnabled = UserDefaults.standard.bool(forKey: "dragEnabled")
        if let d = UserDefaults.standard.data(forKey: "layouts"), let saved = try? JSONDecoder().decode([TileLayout].self, from: d) {
            var ids = Set<String>()
            customLayouts = saved.filter { layout in layout.custom && !layout.zones.isEmpty && layout.zones.count <= 9 && layout.zones.allSatisfy(\.isValid) && ids.insert(layout.id).inserted && !TileLayout.presets.contains(where: { $0.id == layout.id }) }
        }
    }
    func save(_ name: String, zones: [TileZone]) {
        guard !zones.isEmpty, zones.count <= 9, zones.allSatisfy(\.isValid) else { return }
        let l = TileLayout(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ma disposition" : name, subtitle: "Un espace à ta mesure.", symbol: "rectangle.3.group", zones: zones, custom: true)
        customLayouts.append(l); selectedLayoutID = l.id; persist()
    }
    func removeCurrent() { guard layout.custom else { return }; customLayouts.removeAll { $0.id == selectedLayoutID }; selectedLayoutID = "duo"; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(customLayouts) { UserDefaults.standard.set(data, forKey: "layouts") } }
}
enum Theme {
    static let bg = Color(red: 0.055, green: 0.065, blue: 0.085)
    static let panel = Color(red: 0.085, green: 0.098, blue: 0.125)
    static let raised = Color(red: 0.12, green: 0.135, blue: 0.17)
    static let ink = Color(red: 0.92, green: 0.94, blue: 0.96)
    static let muted = Color(red: 0.55, green: 0.60, blue: 0.67)
    static let mint = Color(red: 0.55, green: 0.92, blue: 0.79)
    static let colors: [Color] = [mint, Color(red: 0.64,green: 0.69,blue: 1), Color(red: 1,green: 0.76,blue: 0.55), Color(red: 0.93,green: 0.63,blue: 0.77)]
}
struct Surface: ViewModifier {
    func body(content: Content) -> some View { content.background(Theme.panel, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.065))) }
}
extension View { func surface() -> some View { modifier(Surface()) } }
struct TileButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
            .foregroundStyle(primary ? Theme.bg : Theme.ink)
            .background(primary ? Theme.mint.opacity(configuration.isPressed ? 0.7 : 1) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 9))
    }
}
struct KeyCap: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11,weight: .medium,design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal,7).padding(.vertical,5).background(.white.opacity(0.045),in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.08))) }
}

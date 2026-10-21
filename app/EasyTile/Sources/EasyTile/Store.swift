import AppKit
import SwiftUI

@MainActor
final class TileStore: ObservableObject {
    @Published var selectedLayoutID = "duo"
    @Published var page = "layouts"
    @Published var gap: Double { didSet { defaults.set(gap, forKey: "gap") } }
    @Published var customLayouts: [TileLayout] = []
    @Published var dragEnabled: Bool { didSet { defaults.set(dragEnabled, forKey: "dragEnabled") } }
    @Published var showEditor = false
    var showPalette: (() -> Void)?
    var layouts: [TileLayout] { TileLayout.presets + customLayouts }
    var layout: TileLayout { layouts.first { $0.id == selectedLayoutID } ?? layouts[0] }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gap = defaults.object(forKey: "gap") == nil ? 12 : min(max(defaults.double(forKey: "gap"),0),32)
        // Enable the new automatic menu once, including upgrades from the old Option-only mode.
        if !defaults.bool(forKey: "automaticDragMenuMigrated") {
            defaults.set(true, forKey: "dragEnabled")
            defaults.set(true, forKey: "automaticDragMenuMigrated")
        }
        dragEnabled = defaults.bool(forKey: "dragEnabled")
        if let d = defaults.data(forKey: "layouts"), let saved = try? JSONDecoder().decode([TileLayout].self, from: d) {
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
    private func persist() { if let data = try? JSONEncoder().encode(customLayouts) { defaults.set(data, forKey: "layouts") } }
}
enum Theme {
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("EasyTile." + name)) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let bg = adaptive("background", light: 0xF4F6F8, dark: 0x0D0E13)
    static let panel = adaptive("panel", light: 0xFFFFFF, dark: 0x16181F)
    static let raised = adaptive("raised", light: 0xE7EBEF, dark: 0x20242D)
    static let ink = adaptive("ink", light: 0x17232D, dark: 0xF2F5FA)
    static let muted = adaptive("muted", light: 0x556474, dark: 0x9CA6BA)
    static let mint = adaptive("mint", light: 0x11694F, dark: 0x9CF7CC)
    static let onAccent = adaptive("onAccent", light: 0xFFFFFF, dark: 0x0D0E13)
    static let warning = adaptive("warning", light: 0x915519, dark: 0xFFC291)
    static let border = ink.opacity(0.13)
    static let colors: [Color] = [mint,
        adaptive("violet", light: 0x6551A8, dark: 0xB5ADFF),
        warning, adaptive("rose", light: 0xA94470, dark: 0xFAA8CC)]
}
struct TilePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle()).opacity(configuration.isPressed ? 0.7 : 1)
    }
}
enum AppVersion {
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Développement" }
}
struct Surface: ViewModifier {
    func body(content: Content) -> some View { content.background(Theme.panel, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.ink.opacity(0.065))) }
}
extension View { func surface() -> some View { modifier(Surface()) } }
struct TileButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle()).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .background(primary ? Theme.mint.opacity(configuration.isPressed ? 0.7 : 1) : Theme.ink.opacity(configuration.isPressed ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
    }
}
struct KeyCap: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11,weight: .medium,design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal,7).padding(.vertical,5).background(Theme.ink.opacity(0.045),in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.ink.opacity(0.08))) }
}

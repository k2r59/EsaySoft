import AppKit
import SwiftUI
import ImageIO

enum Theme {
    // Named dynamic colors are resolved by the window's effective appearance.
    // Switching themes changes presentation only: no history reload or image decoding.
    static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("EasyPaste." + name)) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let bg = adaptive("background", light: 0xF4F6F8, dark: 0x0D0E13)
    static let panel = adaptive("panel", light: 0xFFFFFF, dark: 0x16181F)
    static let raised = adaptive("raised", light: 0xE7EBEF, dark: 0x20242D)
    static let ink = adaptive("ink", light: 0x17232D, dark: 0xF2F5FA)
    static let muted = adaptive("muted", light: 0x556474, dark: 0x9CA6BA)
    static let mint = adaptive("accent", light: 0x11694F, dark: 0x9CF7CC)
    static let onAccent = adaptive("onAccent", light: 0xFFFFFF, dark: 0x0D0E13)
    static let warning = adaptive("warning", light: 0x915519, dark: 0xFFC291)
    static let danger = adaptive("danger", light: 0xB52D37, dark: 0xFF8C95)
    static let border = ink.opacity(0.13)
    static let hoverBorder = ink.opacity(0.28)
    static let colors: [Color] = [mint,
        adaptive("violet", light: 0x6551A8, dark: 0xB5ADFF),
        adaptive("amber", light: 0x915519, dark: 0xFFC291),
        adaptive("rose", light: 0xA94470, dark: 0xFAA8CC)]
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.19).fill(Theme.colors[1]).frame(width: size * 0.65, height: size * 0.72).rotationEffect(.degrees(-9)).offset(x: -size * 0.11, y: -size * 0.06)
            RoundedRectangle(cornerRadius: size * 0.19).fill(LinearGradient(colors: [Color(red: 0.76, green: 1, blue: 0.88), Theme.mint], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: size * 0.65, height: size * 0.72).rotationEffect(.degrees(7)).offset(x: size * 0.12, y: size * 0.10)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct Surface: ViewModifier {
    func body(content: Content) -> some View { content.background(Theme.panel, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.border)) }
}
extension View { func surface() -> some View { modifier(Surface()) } }
/// Keep the entire label interactive, including transparent padding and spacers.
/// Apply this inside the button style so native button actions, keyboard activation
/// and disabled states all use the same bounds without an extra tap gesture.
struct FullAreaButtonStyle: ButtonStyle {
    var minimumSize: CGFloat = 0
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: minimumSize, minHeight: minimumSize)
            .contentShape(.interaction, Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
struct PasteButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .background(primary ? Theme.mint.opacity(configuration.isPressed ? 0.75 : 1) : Theme.ink.opacity(configuration.isPressed ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(primary ? Theme.mint : Theme.border))
            .contentShape(.interaction, Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
struct KeyCap: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal, 7).padding(.vertical, 5).background(Theme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border)) }
}
enum ArtworkCache {
    static let hero: NSImage? = {
        var url = Bundle.main.url(forResource: "clipboard-studio", withExtension: "png")
        #if DEBUG
        if url == nil { url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/clipboard-studio.png") }
        #endif
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 720, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }()
}
struct HeroArtwork: View {
    var body: some View {
        Group {
            if let image = ArtworkCache.hero { Image(nsImage: image).resizable().scaledToFit() }
            else { BrandMark(size: 100) }
        }.frame(width: 270, height: 165).accessibilityHidden(true)
    }
}

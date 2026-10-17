import AppKit
import SwiftUI
import ImageIO

enum Theme {
    static let bg = Color(red: 0.050, green: 0.055, blue: 0.075)
    static let panel = Color(red: 0.085, green: 0.095, blue: 0.120)
    static let raised = Color(red: 0.125, green: 0.140, blue: 0.175)
    static let ink = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let muted = Color(red: 0.61, green: 0.65, blue: 0.73)
    static let mint = Color(red: 0.61, green: 0.97, blue: 0.80)
    static let colors: [Color] = [mint, Color(red: 0.71, green: 0.68, blue: 1), Color(red: 1, green: 0.76, blue: 0.57), Color(red: 0.98, green: 0.66, blue: 0.80)]
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
    func body(content: Content) -> some View { content.background(Theme.panel, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.075))) }
}
extension View { func surface() -> some View { modifier(Surface()) } }
struct PasteButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(primary ? Theme.bg : Theme.ink)
            .background(primary ? Theme.mint.opacity(configuration.isPressed ? 0.75 : 1) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(primary ? Color.white.opacity(0.25) : Color.white.opacity(0.07)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
struct KeyCap: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal, 7).padding(.vertical, 5).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.08))) }
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

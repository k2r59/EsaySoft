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
    // Free-standing library labels share one continuous contrast coating.
    static let chromeSecondary = adaptive("chrome.secondary", light: 0x334353, dark: 0xBBC7D9)
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
    @ThemePalette private var palette
    var size: CGFloat = 34
    var body: some View {
        Group {
            if let image = ArtworkCache.brand {
                ZStack {
                    Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                        .foregroundStyle(palette.markGradient)
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .saturation(0).blendMode(.softLight).opacity(0.18)
                }.compositingGroup()
                    .shadow(color: Theme.panel.opacity(0.9), radius: 0.7)
            } else {
                Image(systemName: "doc.on.doc.fill").font(.system(size: size * 0.55)).foregroundStyle(palette.accent)
            }
        }.frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Surface: ViewModifier {
    @ThemePalette private var palette
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View { content.background(Theme.panel, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(contrast == .increased ? Theme.ink.opacity(0.5) : palette.accent.opacity(0.10))) }
}
extension View { func surface() -> some View { modifier(Surface()) } }

/// One native backdrop for the whole window. Opacity belongs to the backdrop,
/// never the window or its text. Cards retain an opaque reading surface.
struct AppBackdrop: View {
    @AppStorage(GlassTint.defaultsKey) private var storedTint = GlassTint.blue.rawValue
    @AppStorage(GlassAppearance.key) private var transparency = GlassAppearance.defaultTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if contrast == .increased || reduceTransparency { Theme.bg }
            else {
                ZStack {
                    WindowBackdropMaterial().opacity(GlassAppearance.materialOpacity(transparency))
                    Theme.bg.opacity(GlassAppearance.windowReadabilityOpacity(transparency))
                    LinearGradient(colors: GlassTint.resolve(storedTint).windowColors,
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(GlassAppearance.windowTintOpacity(transparency, dark: scheme == .dark))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct WindowBackdropMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
extension View {
    func chromeSurface(radius: CGFloat = 16) -> some View {
        modifier(AppChromeSurface(radius: radius))
    }
    func glassLabelPlate() -> some View { modifier(GlassLabelPlate()) }
    func glassControlFinish(radius: CGFloat, primary: Bool = false) -> some View {
        modifier(GlassControlFinish(radius: radius, primary: primary))
    }
}

/// Static specular light, without another blur layer or an animation timer.
/// It sits over the surface only and never changes the control's hit area.
private struct GlassControlFinish: ViewModifier {
    let radius: CGFloat
    let primary: Bool
    @ThemePalette private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.overlay {
            if !reduceTransparency && contrast != .increased {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape.fill(LinearGradient(colors: [.white.opacity(primary ? 0.08 : (scheme == .dark ? 0.025 : 0.08)), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [scheme == .dark ? palette.accent.opacity(0.16) : .white.opacity(0.72), scheme == .dark ? palette.accent.opacity(0.04) : .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

/// Protect labels from an arbitrary desktop without making the entire glass opaque.
private struct GlassLabelPlate: ViewModifier {
    @ThemePalette private var palette
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 10).fill(palette.controlPlate.opacity(0.95))
                .glassControlFinish(radius: 10)
        }
    }
}

/// EasyPaste's palette stays outside the editor material shared with EasyShoot.
private struct AppChromeSurface: ViewModifier {
    let radius: CGFloat
    @ThemePalette private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.chromeGlass(base: Theme.panel, radius: radius)
        } else {
            material(content: content)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(
                        LinearGradient(colors: [scheme == .dark ? palette.accent.opacity(0.16) : .white.opacity(0.85), palette.accent.opacity(0.14), scheme == .dark ? palette.accent.opacity(0.04) : .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
        }
    }
    @ViewBuilder private func material(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let plate = shape.fill(LinearGradient(colors: [Theme.panel.opacity(0.96), palette.controlPlate.opacity(0.96)], startPoint: .topLeading, endPoint: .bottomTrailing))
        // The readable coating covers the system's neutral rim; the custom
        // edge above supplies the selected palette instead of stacking borders.
        if #available(macOS 26.0, *) {
            content.background { plate.background { Color.clear.glassEffect(.clear, in: shape) } }
        } else {
            content.background { plate.background(.regularMaterial, in: shape) }
        }
    }
}
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
    @ThemePalette private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .background {
                RoundedRectangle(cornerRadius: 11).fill(primary ? AnyShapeStyle(palette.actionGradient) : AnyShapeStyle(palette.controlPlate))
                    .glassControlFinish(radius: 11, primary: primary)
            }
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(contrast == .increased ? Theme.ink.opacity(0.6) : (primary ? palette.accent : palette.accent.opacity(0.12)), lineWidth: contrast == .increased ? 1.5 : 0.75))
            .contentShape(.interaction, Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
struct KeyCap: View {
    @ThemePalette private var palette
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal, 7).padding(.vertical, 5).background(palette.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 5)) }
}
enum ArtworkCache {
    // Decode once at a bounded size for all header marks, rather than loading
    // the full app-icon artwork during every SwiftUI render.
    static let brand: NSImage? = {
        var url = Bundle.main.url(forResource: "easypaste-ribbon-mark", withExtension: "png") ?? Bundle.main.url(forResource: "easypaste-ribbon", withExtension: "png")
        #if DEBUG
        if url == nil { url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/easypaste-ribbon-mark.png") }
        #endif
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }()

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

import SwiftUI

/// Vector artwork stays crisp at every display scale.
struct ShelfBrandMark: View {
    var body: some View {
        BrandMark(size: 40)
    }
}

enum GlassAppearance {
    static let key = "quickBarGlassTransparency"
    static let defaultTransparency = 0.45
    static func transparency(_ value: Double) -> Double { value.isFinite ? min(0.8, max(0, value)) : defaultTransparency }
    static func washOpacity(_ value: Double, dark: Bool = false) -> Double {
        let amount = transparency(value)
        // Only the frame becomes transparent. Reading cards and control plates
        // keep their own contrast, independently of this slider and the desktop.
        return 1 - amount
    }
    static func windowTintOpacity(_ value: Double, dark: Bool) -> Double {
        washOpacity(value, dark: dark)
    }
    // A single continuous coating lets library labels sit directly on glass.
    // The desktop remains visible, but cannot invert label contrast at 80 %.
    static func windowReadabilityOpacity(_ value: Double) -> Double {
        1 - 0.3 * transparency(value)
    }
    static func materialOpacity(_ value: Double) -> Double {
        1 - 0.65 * transparency(value) / 0.8
    }
    // The desktop contributes to the frame, never to the reading surfaces.
    static let ice = Theme.adaptive("glass.ice", light: 0x7FAFF2, dark: 0x234F76)
    static let blue = Theme.adaptive("glass.blue", light: 0x50ABF0, dark: 0x1B3863)
    static let aqua = Theme.adaptive("glass.aqua", light: 0x79D8DF, dark: 0x235663)
    static let labelPlate = Theme.adaptive("glass.labelPlate", light: 0xE3F1FC, dark: 0x1B2C40)
    static let action = Theme.adaptive("glass.action", light: 0x00866A, dark: 0x9CF7CC)
    static let selection = Color(red: 0, green: 0.73, blue: 0.57)
    static let selectedTab = Theme.adaptive("glass.selectedTab", light: 0xCEF4E9, dark: 0x123D36)
}

/// A single, stationary lighting layer. No per-card blur, timer or animated shader.
struct ShelfGlassWash: View {
    let transparency: Double
    var tint: GlassTint = .blue
    @Environment(\.colorScheme) private var scheme
    private var light: Double { scheme == .dark ? 0.1 : 1 }
    var body: some View {
        LinearGradient(stops: [
            .init(color: tint.colors[0], location: 0),
            .init(color: tint.colors[1], location: 0.26),
            .init(color: tint.colors[2], location: 0.50),
            .init(color: tint.colors[2], location: 0.62),
            .init(color: tint.colors[1], location: 1)
        ], startPoint: .leading, endPoint: .trailing)
        .opacity(GlassAppearance.washOpacity(transparency, dark: scheme == .dark))
        .overlay {
            LinearGradient(stops: [
                .init(color: .white.opacity(0.42 * light), location: 0),
                .init(color: .white.opacity(0.04 * light), location: 0.22),
                .init(color: .white.opacity(0.12 * light), location: 0.45),
                .init(color: .clear, location: 0.63),
                .init(color: .white.opacity(0.10 * light), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ShelfGlassRim: View {
    let shape: ShelfOutline
    @Environment(\.colorScheme) private var scheme
    private var strength: Double { scheme == .dark ? 0.55 : 1 }
    var body: some View {
        ZStack {
            shape.strokeBorder(.white.opacity(0.18 * strength), lineWidth: 9)
            shape.strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity(strength), location: 0),
                .init(color: .white.opacity(0.65 * strength), location: 0.45),
                .init(color: .white.opacity(strength), location: 0.76),
                .init(color: .white.opacity(0.68 * strength), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
            if scheme != .dark {
                shape.inset(by: 2.7).strokeBorder(Color(red: 0.19, green: 0.49, blue: 0.78).opacity(0.22), lineWidth: 0.7)
            }
            shape.inset(by: 4).strokeBorder(LinearGradient(colors: [
                .white.opacity(0.75 * strength), .white.opacity(0.12), .white.opacity(0.52 * strength)
            ], startPoint: .top, endPoint: .bottomTrailing), lineWidth: 1)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Compact preview actions keep a stable hit area and native button semantics.
struct ShelfActionButtonStyle: ButtonStyle {
    var primary = false
    @ThemePalette private var palette
    @AppStorage(GlassAppearance.key) private var transparency = GlassAppearance.defaultTransparency
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 17, weight: .medium))
            .frame(width: 40, height: 40)
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(primary ? AnyShapeStyle(palette.actionGradient) : AnyShapeStyle(palette.controlPlate.opacity(reduceTransparency || contrast == .increased ? 1 : 0.95 - 0.12 * GlassAppearance.transparency(transparency))))
                    .glassControlFinish(radius: 12, primary: primary)
            }
            .overlay {
                if contrast == .increased { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink.opacity(0.6), lineWidth: 1.5) }
            }
            .contentShape(Rectangle()).opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
    }
}

/// A short, centred light reflection separates the preview from navigation.
/// Both ends fade out; no enclosing band, full-width rail or extra material.
struct ShelfGlassSeparator: View {
    @ThemePalette private var palette
    @AppStorage(GlassAppearance.key) private var transparency = GlassAppearance.defaultTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var light: Double { (scheme == .dark ? 0.38 : 0.95) * (1 - 0.25 * GlassAppearance.transparency(transparency)) }
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(light * 0.7), location: 0.18),
                .init(color: .white.opacity(light), location: 0.5),
                .init(color: .white.opacity(light * 0.7), location: 0.82),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
                .shadow(color: .white.opacity(light * 0.25), radius: 1)
            Rectangle().fill(LinearGradient(colors: [.clear, palette.accent.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 0.5)
        }
        .opacity(reduceTransparency || contrast == .increased ? 0 : 1)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlassAppearanceSettings: View {
    @AppStorage(GlassAppearance.key) private var transparency = GlassAppearance.defaultTransparency
    @AppStorage(GlassTint.defaultsKey) private var storedTint = GlassTint.blue.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var percentage: Int { Int((GlassAppearance.transparency(transparency) * 100).rounded()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Teinte du verre").font(.system(size: 12, weight: .medium))
            HStack(spacing: 10) {
                ForEach(GlassTint.allCases) { tint in
                    Button { storedTint = tint.rawValue } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: tint.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(height: 38)
                            HStack(spacing: 4) {
                                Text(tint.title)
                                Image(systemName: "checkmark").opacity(GlassTint.resolve(storedTint) == tint ? 1 : 0)
                            }.font(.system(size: 11, weight: .medium))
                        }.padding(8).frame(maxWidth: .infinity)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(GlassTint.resolve(storedTint) == tint ? tint.accent : Theme.border, lineWidth: GlassTint.resolve(storedTint) == tint ? 2 : 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(FullAreaButtonStyle())
                        .accessibilityLabel("Teinte du verre : \(tint.title)")
                        .accessibilityAddTraits(GlassTint.resolve(storedTint) == tint ? .isSelected : [])
                }
            }.padding(.bottom, 10)
            HStack {
                Text("Transparence du verre").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(percentage) %").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted).monospacedDigit()
                Button("Réinitialiser") { transparency = GlassAppearance.defaultTransparency }.buttonStyle(FullAreaButtonStyle()).font(.system(size: 11)).help("Rétablir la transparence à 45 %")
            }
            Slider(value: Binding(get: { GlassAppearance.transparency(transparency) }, set: { transparency = $0 }), in: 0...0.8, step: 0.05)
                .accessibilityLabel("Transparence du verre").accessibilityValue("\(percentage) pour cent")
                .disabled(reduceTransparency || contrast == .increased)
            HStack { Text("Plus lisible"); Spacer(); Text("Plus transparent") }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(reduceTransparency || contrast == .increased ? "Le réglage d’accessibilité de macOS impose un fond opaque." : "Fenêtre, barre rapide et aperçus. Les zones de lecture restent opaques.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
}

/// Two portrait sheets, matching the preview action without a clipboard clip.
struct ShelfPasteSymbol: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 13.5, y: 3)); p.addLine(to: CGPoint(x: 13.5, y: 2))
            p.addQuadCurve(to: CGPoint(x: 12, y: 0.5), control: CGPoint(x: 13.5, y: 0.5))
            p.addLine(to: CGPoint(x: 2, y: 0.5)); p.addQuadCurve(to: CGPoint(x: 0.5, y: 2), control: CGPoint(x: 0.5, y: 0.5))
            p.addLine(to: CGPoint(x: 0.5, y: 16)); p.addQuadCurve(to: CGPoint(x: 2, y: 17.5), control: CGPoint(x: 0.5, y: 17.5))
            p.addLine(to: CGPoint(x: 3, y: 17.5))
            p.addRoundedRect(in: CGRect(x: 5.5, y: 4.5, width: 13, height: 17), cornerSize: CGSize(width: 1.5, height: 1.5))
        }.transform(CGAffineTransform(scaleX: 0.8, y: 0.8))
            .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 18).accessibilityHidden(true)
    }
}

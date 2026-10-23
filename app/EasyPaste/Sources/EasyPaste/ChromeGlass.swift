import AppKit
import SwiftUI

/// Reserved for fixed navigation and toolbars. Reading surfaces stay opaque;
/// never attach a material to each scrolling card or to the rendered image.
struct ChromeGlassModifier: ViewModifier {
    let base: Color
    var radius: CGFloat = 16
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency || contrast == .increased {
                content.background(base, in: shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 2).allowsHitTesting(false))
            } else if #available(macOS 26.0, *) {
                // Apply the native material to the actual content. A filled
                // sibling background hides refraction and prevents adaptation.
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.11), lineWidth: 1).allowsHitTesting(false))
            }
        }
    }
}

extension View {
    func chromeGlass(base: Color, radius: CGFloat = 16) -> some View {
        modifier(ChromeGlassModifier(base: base, radius: radius))
    }
}

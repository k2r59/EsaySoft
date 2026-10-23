import AppKit
import SwiftUI

/// One shared glass layer for the shelf. Cards and text are never rendered into
/// translucent layers, and scrolling does not create a material per card.
struct ShelfGlass: View {
    var nativeHosted = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        if reduceTransparency || contrast == .increased {
            ShelfGlassSurface(opaque: true)
        } else if !nativeHosted {
            ShelfGlassSurface(opaque: false)
        }
    }
}

struct ShelfGlassSurface: View {
    let opaque: Bool
    private let shape = RoundedRectangle(cornerRadius: 23, style: .continuous)

    var body: some View {
        Group {
            if opaque {
                shape.fill(Theme.raised)
            } else if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.clear, in: shape)
            } else {
                ShelfMaterial().clipShape(shape)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

@MainActor enum ShelfHosting {
    static func make(history: History) -> NSView {
        let host = NSHostingView(rootView: ShelfRootView(history: history))
        // AppKit must not resize the panel to SwiftUI's changing intrinsic size.
        host.sizingOptions = []
        return host
    }
}

private struct ShelfMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}


/// SwiftUI owns the visible expansion. The window only reserves space first and
/// releases it after collapse, so two independent animations cannot move the bar.
@MainActor final class ShelfWindowSizer {
    private var shrinkTask: Task<Void, Never>?
    private let releaseDelay: Duration
    init(releaseDelay: Duration = .milliseconds(260)) { self.releaseDelay = releaseDelay }
    func cancel() { shrinkTask?.cancel(); shrinkTask = nil }
    func resize(_ panel: NSPanel, to target: CGRect, deferShrink: Bool) {
        cancel()
        if deferShrink, target.height < panel.frame.height {
            let delay = releaseDelay
            shrinkTask = Task { @MainActor [weak self, weak panel] in
                do { try await Task.sleep(for: delay) } catch { return }
                guard !Task.isCancelled, let self, let panel else { return }
                panel.setFrame(target, display: true)
                self.shrinkTask = nil
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }
}

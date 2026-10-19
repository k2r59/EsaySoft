import AppKit
import SwiftUI

struct SampledColor: Equatable, Sendable {
    let red: Int, green: Int, blue: Int
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var rgb: String { "rgb(\(red), \(green), \(blue))" }
    var color: Color { Color(.sRGB, red: Double(red)/255, green: Double(green)/255, blue: Double(blue)/255) }
    init?(_ color: NSColor) {
        guard let value = color.usingColorSpace(.sRGB) else { return nil }
        let channels = [value.redComponent, value.greenComponent, value.blueComponent]
        guard channels.allSatisfy(\.isFinite) else { return nil }
        let bytes = channels.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        red = bytes[0]; green = bytes[1]; blue = bytes[2]
    }
    var clip: Clip {
        let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(hex.utf8))]])
        return Clip(title: hex, text: hex, source: "Pipette EasyPaste", sourceID: "app.easypaste.mac", kind: .color, fingerprint: Clip.fingerprint(payload), payload: payload)
    }
}

@MainActor final class ColorSamplerController {
    typealias Presenter = (@escaping @MainActor (NSColor?) -> Void) -> Void
    private let history: History
    private var sampler: NSColorSampler?
    private var panel: NSPanel?
    private var operation: UUID?
    var presentResult: ((SampledColor, Bool) -> Void)?
    var beforeSampling: (() -> Void)?
    init(history: History) { self.history = history }
    func sample(presenter: Presenter? = nil, pasteboard: NSPasteboard = .general) {
        guard !history.samplingColor, !history.captureBusy, !history.recording, !history.annotating, !history.loading, !history.fault else { return }
        panel?.orderOut(nil); panel = nil; beforeSampling?()
        history.samplingColor = true; let id = UUID(); operation = id
        let completion: @MainActor (NSColor?) -> Void = { [weak self] color in
            guard let self, self.operation == id else { return }
            self.operation = nil; self.sampler = nil
            guard let color else { self.history.samplingColor = false; return }
            guard let sample = SampledColor(color) else {
                self.history.samplingColor = false; self.history.report("Cette couleur ne peut pas être convertie en sRGB."); return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.history.samplingColor = false }
                do {
                    _ = try await self.history.insertCapture(sample.clip)
                    let copied = self.history.copyStructuredText(sample.hex, to: pasteboard)
                    if let presentResult = self.presentResult { presentResult(sample, copied) }
                    else { self.show(sample, copied: copied) }
                } catch { self.history.report("Couleur non enregistrée : \(error.localizedDescription)") }
            }
        }
        if let presenter { presenter(completion) }
        else {
            let sampler = NSColorSampler(); self.sampler = sampler
            sampler.show { color in MainActor.assumeIsolated { completion(color) } }
        }
    }
    private func show(_ sample: SampledColor, copied: Bool) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Pipette EasyPaste"; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.backgroundColor = NSColor(Theme.bg)
        panel.contentView = NSHostingView(rootView: ColorSampleView(sample: sample, copied: copied, copy: { [weak self] text in
            self?.history.copyStructuredText(text) ?? false
        }, again: { [weak self] in self?.sample() }, close: { [weak self] in self?.panel?.close(); self?.panel = nil }))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: frame.midX-panel.frame.width/2, y: frame.midY-panel.frame.height/2))
        } else { panel.center() }
        self.panel = panel; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct ColorSampleView: View {
    let sample: SampledColor
    let copied: Bool
    let copy: (String) -> Bool
    let again: () -> Void
    let close: () -> Void
    @State private var feedback: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Couleur prélevée", systemImage: "eyedropper").font(.system(size: 19, weight: .semibold))
                Spacer()
                Text("sRGB").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
                    .help("Les couleurs de l’écran sont converties en sRGB pour le web.")
            }
            RoundedRectangle(cornerRadius: 16).fill(sample.color).frame(height: 145)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.16)))
                .accessibilityLabel("Aperçu de la couleur \(sample.hex)")
            VStack(spacing: 8) {
                valueRow("HEX", sample.hex)
                valueRow("RGB", sample.rgb)
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                Text(feedback ?? (copied ? "HEX copié · couleur dans l’historique" : "Couleur ajoutée à l’historique"))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.frame(height: 18)
            HStack {
                Button("Fermer", action: close).buttonStyle(PasteButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: again) { Label("Prélever à nouveau", systemImage: "eyedropper") }
                    .buttonStyle(PasteButtonStyle(primary: true))
            }
        }.padding(24).frame(width: 430).background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
    private func valueRow(_ label: String, _ text: String) -> some View {
        Button {
            feedback = copy(text) ? "\(label) copié · ⌘V pour coller" : "Copie impossible."
        } label: {
            HStack(spacing: 14) {
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).frame(width: 32, alignment: .leading)
                Text(text).font(.system(size: 15, weight: .medium, design: .monospaced))
                Spacer()
                Image(systemName: "square.on.square").foregroundStyle(Theme.mint)
            }.padding(14).frame(maxWidth: .infinity).background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(FullAreaButtonStyle()).accessibilityLabel("Copier \(label) : \(text)")
    }
}

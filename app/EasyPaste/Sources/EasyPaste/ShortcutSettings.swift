import SwiftUI
import AppKit

struct ShortcutSettings: View {
    @ObservedObject var shortcuts: KeyboardShortcuts
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clique sur une combinaison pour la modifier.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            group("Depuis n’importe quelle application", [.shelf, .capture, .ocr, .stop, .stack])
            Divider().opacity(0.3)
            group("Dans EasyPaste", [.search, .edit, .preview, .paste, .plainPaste])
            SettingsDetails("Collage rapide des cartes") {
                ForEach(ShortcutAction.cards) { row($0) }
                Text("Ajoute ⇧ pour coller en texte brut.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            HStack {
                if let error = shortcuts.error, shortcuts.recording == nil { Text(error).foregroundStyle(Theme.danger).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
                Spacer()
                Button("Rétablir les raccourcis d’origine") { shortcuts.reset() }
                    .buttonStyle(PasteButtonStyle()).disabled(shortcuts.bindings == KeyboardShortcuts.initial)
            }
        }.sheet(item: $shortcuts.recording, onDismiss: { shortcuts.end() }) { action in
            ShortcutRecordingSheet(shortcuts: shortcuts, action: action)
        }
    }
    private func group(_ title: String, _ actions: [ShortcutAction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.bottom, 5)
            ForEach(actions) { row($0) }
        }
    }
    private func row(_ action: ShortcutAction) -> some View {
        HStack(spacing: 10) {
            Text(action.title).font(.system(size: 13))
            Spacer(minLength: 16)
            Button { shortcuts.begin(action) } label: {
                Text(shortcuts[action].display).font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(width: 106, height: 16).contentShape(Rectangle())
            }.buttonStyle(PasteButtonStyle()).accessibilityLabel("Modifier le raccourci : \(action.title)")
                .accessibilityValue(shortcuts[action].display).help("Modifier le raccourci")
            Button { shortcuts.reset(action) } label: { Image(systemName: "arrow.counterclockwise").frame(width: 30, height: 36) }
                .buttonStyle(FullAreaButtonStyle()).disabled(shortcuts[action] == action.initial)
                .accessibilityLabel("Rétablir le raccourci : \(action.title)").help("Par défaut : \(action.initial.display)")
        }.frame(minHeight: 44)
    }
}

private struct ShortcutRecordingSheet: View {
    @ObservedObject var shortcuts: KeyboardShortcuts
    let action: ShortcutAction
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: KeyboardBinding?
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(action.title).font(.system(size: 21, weight: .semibold))
            Text("Appuie sur les touches du nouveau raccourci.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            ShortcutCapture(received: receive, cancel: { dismiss() })
                .frame(height: 76)
                .background(Theme.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.mint, lineWidth: 2).allowsHitTesting(false))
                .overlay(Text(candidate?.display ?? "Nouvelle combinaison…").font(.system(size: 19, weight: .medium, design: .monospaced)).allowsHitTesting(false))
            Text(issue ?? shortcuts.error ?? "Actuel : \(shortcuts[action].display) · Échap pour annuler")
                .font(.system(size: 12)).foregroundStyle(issue == nil && shortcuts.error == nil ? Theme.muted : Theme.danger)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 32, alignment: .topLeading)
            HStack {
                Button("Annuler") { dismiss() }.buttonStyle(PasteButtonStyle())
                Spacer()
                Button("Enregistrer") { if let candidate, shortcuts.set(action, to: candidate) { dismiss() } }
                    .buttonStyle(PasteButtonStyle(primary: true)).disabled(candidate == nil || issue != nil)
            }
        }.padding(26).frame(width: 440).chromeSurface(radius: 20).foregroundStyle(Theme.ink)
    }
    private func receive(_ event: NSEvent) {
        shortcuts.error = nil
        guard let binding = KeyboardBinding.capture(event) else { issue = "Cette touche ne peut pas être utilisée seule."; candidate = nil; return }
        candidate = binding
        var next = shortcuts.bindings; next[action] = binding
        issue = KeyboardShortcuts.validation(next)
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    let received: (NSEvent) -> Void
    let cancel: () -> Void
    func makeNSView(context: Context) -> ShortcutCaptureView { let view = ShortcutCaptureView(); view.received = received; view.cancel = cancel; return view }
    func updateNSView(_ view: ShortcutCaptureView, context: Context) { view.received = received; view.cancel = cancel }
}
final class ShortcutCaptureView: NSView {
    var received: ((NSEvent) -> Void)?
    var cancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setAccessibilityElement(true); setAccessibilityRole(.textField)
        setAccessibilityLabel("Saisir un raccourci clavier")
        DispatchQueue.main.async { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self) }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { cancel?(); return }
        if event.keyCode == 48 { if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) } else { window?.selectNextKeyView(self) }; return }
        received?(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
}

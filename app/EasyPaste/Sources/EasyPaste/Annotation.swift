import AppKit
import SwiftUI

@MainActor final class AnnotationController: NSObject, NSWindowDelegate {
    private let history: History
    private var window: NSPanel?
    private var model: AnnotationModel?
    private var clip: Clip?
    private var actions: AnnotationActions?
    var onSaved: (() -> Void)?
    var isKeyWindow: Bool { window?.isKeyWindow == true }
    func key(_ event: NSEvent) -> NSEvent? {
        guard let model, !model.saving else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "s" {
            if model.dirty { save(copyToClipboard: model.copyToClipboard) }; return nil
        }
        if !(window?.firstResponder is NSTextView), flags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if flags.contains(.shift) { model.redo() } else { model.undo() }; return nil
        }
        return event
    }
    init(history: History) { self.history = history }
    func open(_ clip: Clip) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        guard !history.annotating else { return }; history.annotating = true
        Task { [self] in
            do {
                let full = try await history.fullClip(clip)
                guard let data = full.imageData else { throw CaptureFailure.message("Image introuvable.") }
                let prepared = try await Task.detached(priority: .userInitiated) { try AnnotationModel.prepare(data) }.value
                let model = AnnotationModel(data: data, image: prepared.0, size: prepared.1)
                self.model = model; self.clip = clip; actions = AnnotationActions(model:model)
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { throw CaptureFailure.message("Aucun écran disponible.") }
                let frame = screen.visibleFrame
                let width = min(1320, frame.width-40), height = min(850, frame.height-55)
                let panel = NSPanel(contentRect: CGRect(x: frame.midX-width/2, y: frame.midY-height/2, width: width, height: height), styleMask: [.titled,.closable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
                panel.title = "Annoter la capture"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.isReleasedWhenClosed = false
                panel.minSize = CGSize(width: 1080, height: 700); panel.level = .floating; panel.delegate = self; panel.isOpaque = false; panel.backgroundColor = .clear; panel.titlebarAppearsTransparent = true
                panel.contentView = NSHostingView(rootView: AnnotationView(model: model, cancel: { [weak self] in self?.requestClose() }, save: { [weak self] _, copy in self?.save(copyToClipboard: copy) }, copy:{ [weak self] in self?.actions?.copy() }, export:{ [weak self] in self?.actions?.export() }, pin:{ [weak self] in self?.actions?.pin() }, dragProvider:{ [weak self] in self?.actions?.provider() ?? NSItemProvider() }, allowReplacement: false).ignoresSafeArea(.container,edges:.top))
                window = panel; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            } catch { history.annotating = false; history.report(error.localizedDescription) }
        }
    }
    func requestClose() { if canClose() { close() } }
    private func canClose() -> Bool {
        guard model?.saving != true else { return false }
        guard model?.dirty == true else { return true }
        let alert = NSAlert(); alert.messageText = "Abandonner les annotations ?"; alert.informativeText = "L’original reste dans ton historique. Les modifications n’ont pas encore été enregistrées."; alert.addButton(withTitle: "Continuer à modifier"); alert.addButton(withTitle: "Abandonner")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if canClose() { close() }; return false }
    private func close() { window?.orderOut(nil); window = nil; model = nil; actions = nil; clip = nil; history.annotating = false }
    private func save(copyToClipboard: Bool) {
        guard let model, let clip, !model.saving else { return }
        if model.textPoint != nil { model.addText() }
        model.saving = true; model.error = ""
        let data = model.data, snapshot = model.snapshot, background = model.customBackground
        Task {
            do {
                let png = try await Task.detached(priority: .userInitiated) { try AnnotationRenderer.export(data: data, snapshot: snapshot, customBackground:background) }.value
                let saved = try await history.saveImage(png, parent: clip)
                let copied = copyToClipboard ? await history.copy([saved]) : false; close(); onSaved?()
                let action = "Image enregistrée"
                history.report(copied ? action + " · ⌘V pour coller" : copyToClipboard ? action + ". Utilise Copier pour la préparer." : action + " dans l’historique.")
            } catch { model.saving = false; model.error = error.localizedDescription }
        }
    }
}

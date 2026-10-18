import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation

enum CaptureAction: Int, CaseIterable {
    case area, window, screen, text, video
    var title: String { switch self { case .area: "Capturer une zone"; case .window: "Capturer une fenêtre"; case .screen: "Capturer l’écran"; case .text: "Extraire le texte d’une zone"; case .video: "Enregistrer une vidéo…" } }
    var icon: String { switch self { case .area: "viewfinder"; case .window: "macwindow"; case .screen: "display"; case .text: "text.viewfinder"; case .video: "record.circle" } }
}
struct CaptureMenu: View {
    @ObservedObject var history: History
    var body: some View {
        Menu {
            ForEach(CaptureAction.allCases, id: \.self) { action in
                if action == .text || action == .video { Divider() }
                Button { history.capture?(action) } label: { Label(action.title, systemImage: action.icon) }.disabled(history.captureBusy || history.recording || history.annotating)
            }
            if history.recording { Divider(); Button("Arrêter l’enregistrement") { history.stopRecording?() } }
        } label: { Label(history.recording ? "Enregistrement" : history.captureBusy ? "Capture…" : "Capturer", systemImage: history.recording ? "record.circle.fill" : "viewfinder").font(.system(size: 12, weight: .semibold)).foregroundStyle(history.recording ? .red : Theme.mint).padding(.horizontal, 12).padding(.vertical, 9).background(Theme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).contentShape(.interaction, Rectangle()) }
        .menuStyle(.borderlessButton).fixedSize().help("Capture d’écran, texte et vidéo")
    }
}
struct RecordingSetupView: View {
    @State var options = RecordingOptions()
    let cancel: () -> Void
    let start: (RecordingOptions) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { BrandMark(size: 34); VStack(alignment: .leading, spacing: 4) { Text("Montre plutôt que raconte.").font(.system(size: 22, weight: .semibold)); Text("Une vidéo, directement dans ton historique.").font(.system(size: 12)).foregroundStyle(Theme.muted) } }
            Picker("À enregistrer", selection: $options.area) { Text("Une zone").tag(true); Text("L’écran entier").tag(false) }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 10) {
                PreferenceToggle("Son de l’ordinateur", isOn: $options.systemAudio)
                PreferenceToggle("Microphone", isOn: $options.microphone)
                Divider().opacity(0.3)
                PreferenceToggle("Haute définition · jusqu’à 4K", isOn: $options.fullResolution)
                Text(options.fullResolution ? "30 images/s · fichier plus volumineux" : "Jusqu’à 1080p · 30 images/s · fichier léger").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.toggleStyle(.switch).font(.system(size: 13)).padding(20).surface()
            Label("Décompte de 3 secondes. Arrête depuis le bouton rouge près de l’heure.", systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack { Button("Annuler", action: cancel).buttonStyle(PasteButtonStyle()).keyboardShortcut(.cancelAction); Spacer(); Button("Continuer") { start(options) }.buttonStyle(PasteButtonStyle(primary: true)).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 450).background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
}
@MainActor final class CaptureController: NSObject, NSWindowDelegate {
    let history: History
    private let recorder = Recorder()
    private var overlays: [NSWindow] = []
    private var panel: NSPanel?
    private var selectionContinuation: CheckedContinuation<CGRect?, Never>?
    private var task: Task<Void, Never>?
    private var ticker: Timer?
    private var started: Date?
    private var currentAction: CaptureAction?
    private var operation: UUID?
    var hideApp: (() -> Void)?
    var showResult: (() -> Void)?
    var statusChanged: ((String?) -> Void)?
    init(history: History) {
        self.history = history; super.init()
        recorder.onStart = { [weak self] in
            guard let self else { return }
            self.started = Date(); self.history.recording = true; self.history.captureBusy = false
            self.updateStatus()
            self.ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus(); self?.recorder.checkSize() } }
            self.ticker?.tolerance = 0.1
        }
        recorder.onFinish = { [weak self] result in self?.finishedRecording(result) }
    }
    func run(_ action: CaptureAction) {
        guard !history.captureBusy, !history.recording, !history.annotating, !history.loading, !history.fault else { return }
        let id = UUID(); operation = id; currentAction = action; history.captureBusy = true
        if !CGPreflightScreenCaptureAccess() { showPermission(action); return }
        if action == .video {
            present(RecordingSetupView(cancel: { [weak self] in self?.cancel() }, start: { [weak self] options in self?.beginVideo(options) }), title: "Enregistrer une vidéo")
        } else {
            task = Task { [weak self] in await self?.captureImage(action, id: id) }
        }
    }
    private func showPermission(_ action: CaptureAction) {
        present(VStack(alignment: .leading, spacing: 20) {
            Label("Autoriser la capture d’écran", systemImage: "lock.shield").font(.system(size: 20, weight: .semibold))
            Text("Active EasyPaste dans Confidentialité et sécurité → Enregistrement de l’écran et de l’audio système. Cette autorisation sert aussi aux captures d’image et à la lecture du texte.").fixedSize(horizontal: false, vertical: true).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Text("Si macOS demande de quitter l’app, rouvre EasyPaste depuis Applications.").fixedSize(horizontal: false, vertical: true).font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack { Button("Plus tard") { self.cancel() }.buttonStyle(PasteButtonStyle()); Spacer(); Button("Autoriser…") {
                _ = CGRequestScreenCaptureAccess()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }.buttonStyle(PasteButtonStyle()); Button("Réessayer") { self.dismissPanel(); self.history.captureBusy = false; self.run(action) }.buttonStyle(PasteButtonStyle(primary: true)) }
        }.padding(28).frame(width: 490).background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark), title: "Autorisation EasyPaste")
    }
    private func present<V: View>(_ view: V, title: String) {
        dismissPanel()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled,.closable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.level = .floating; panel.delegate = self
        panel.contentView = NSHostingView(rootView: view); panel.center(); self.panel = panel
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func dismissPanel() { panel?.orderOut(nil); panel = nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
    func cancel() {
        operation = nil; task?.cancel(); task = nil; dismissPanel(); finishSelection(nil)
        if recorder.state != .idle { recorder.stop() } else { history.captureBusy = false; showResult?() }
    }
    private func screenRect() -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return .zero }
        return Self.quartzRect(screen.frame)
    }
    static func quartzRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0)-rect.maxY, width: rect.width, height: rect.height)
    }
    private func select(windows: [SCWindow] = []) async -> CGRect? {
        await withCheckedContinuation { continuation in
            selectionContinuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            for screen in NSScreen.screens {
                let window = SelectionWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.backgroundColor = .clear; window.isOpaque = false; window.level = .screenSaver; window.isReleasedWhenClosed = false
                window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.acceptsMouseMovedEvents = true
                let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                if !windows.isEmpty {
                    view.instruction = "Clique sur une fenêtre · Échap pour annuler"
                    view.windowFrames = windows.map { candidate in
                        let quartzScreen = Self.quartzRect(screen.frame)
                        return CGRect(x: candidate.frame.minX-screen.frame.minX, y: screen.frame.height-(candidate.frame.maxY-quartzScreen.minY), width: candidate.frame.width, height: candidate.frame.height)
                    }
                } else { view.instruction = currentAction == .text ? "Encadre le texte à copier · Échap pour annuler" : "Glisse pour sélectionner une zone · Échap pour annuler" }
                view.done = { [weak self] rect in
                    let result = rect.map { Self.quartzRect($0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)) }
                    self?.finishSelection(result)
                }
                window.contentView = view; overlays.append(window); window.orderFrontRegardless()
                if screen.frame.contains(NSEvent.mouseLocation) { window.makeKey(); window.makeFirstResponder(view) }
            }
        }
    }
    private func finishSelection(_ rect: CGRect?) {
        overlays.forEach { $0.orderOut(nil) }; overlays.removeAll()
        let continuation = selectionContinuation; selectionContinuation = nil; continuation?.resume(returning: rect)
    }
    private func captureImage(_ action: CaptureAction, id: UUID) async {
        let screen = screenRect(); hideApp?()
        defer { if operation == id { history.captureBusy = false; task = nil; operation = nil } }
        do {
            let image: CGImage
            if action == .window {
                let content = try await CaptureImage.content()
                let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? UInt32 }
                let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID,$0) })
                let windows = order.compactMap { byID[$0] }.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 80 && $0.frame.height > 50 }
                guard !windows.isEmpty else { throw CaptureFailure.message("Aucune fenêtre disponible à capturer.") }
                guard let rect = await select(windows: windows), let window = windows.first(where: { $0.frame == rect }) else { if operation == id { showResult?() }; return }
                try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(140))
                image = try await CaptureImage.window(window)
            } else {
                let rect: CGRect
                if action == .screen { rect = screen }
                else { guard let selected = await select() else { if operation == id { showResult?() }; return }; rect = selected }
                try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(140))
                image = try await CaptureImage.region(rect)
            }
            let data = try await Task.detached(priority: .userInitiated) { try CaptureImage.png(image) }.value
            try Task.checkCancellation()
            let clip: Clip
            if action == .text {
                let text = try await Task.detached(priority: .userInitiated) { try ImageText.recognize(data) }.value
                try Task.checkCancellation(); guard operation == id else { return }
                clip = try await history.saveOCR(text)
            } else { clip = try await history.saveImage(data) }
            let copied = await history.copy([clip]); showResult?()
            history.report(copied ? (action == .text ? "Texte extrait · prêt à coller avec ⌘V." : "Capture copiée · survole la carte pour l’annoter.") : "Capture enregistrée dans l’historique.")
        } catch is CancellationError { if operation == id { showResult?() } }
        catch { if operation == id { showResult?(); history.report(error.localizedDescription) } }
    }
    private func beginVideo(_ options: RecordingOptions) {
        guard let id = operation else { return }
        dismissPanel()
        let screen = screenRect()
        task = Task {
            do {
                if options.microphone {
                    let authorized = AVCaptureDevice.authorizationStatus(for: .audio)
                    let granted = authorized == .authorized ? true : authorized == .notDetermined ? await AVCaptureDevice.requestAccess(for: .audio) : false
                    guard granted else { throw CaptureFailure.message("Le microphone n’est pas autorisé. Active-le dans Confidentialité et sécurité → Microphone, ou désactive cette option.") }
                }
                try Task.checkCancellation(); guard operation == id else { return }
                hideApp?()
                let area: CGRect
                if options.area { guard let rect = await select() else { if operation == id { history.captureBusy = false; operation = nil; showResult?() }; return }; area = rect }
                else { area = screen }
                let content = try await CaptureImage.content()
                guard let display = content.displays.first(where: { $0.frame.contains(area) }) else { throw CaptureFailure.message("La zone vidéo doit tenir sur un seul écran.") }
                for count in (1...3).reversed() {
                    try Task.checkCancellation()
                    present(VStack(spacing: 12) { Text("\(count)").font(.system(size: 64, weight: .light, design: .rounded)).foregroundStyle(Theme.mint); Text("L’enregistrement va commencer").foregroundStyle(Theme.muted); Button("Annuler") { self.cancel() }.buttonStyle(PasteButtonStyle()).keyboardShortcut(.cancelAction) }.padding(28).frame(width: 290).background(Theme.bg).preferredColorScheme(.dark), title: "Prêt ?")
                    try await Task.sleep(for: .seconds(1))
                }
                dismissPanel(); try Task.checkCancellation()
                try await recorder.start(display: display, area: area, content: content, options: options)
                task = nil
            } catch is CancellationError { if operation == id { dismissPanel(); history.captureBusy = false; operation = nil; showResult?() } }
            catch { if operation == id { dismissPanel(); history.captureBusy = false; operation = nil; showResult?(); history.report(error.localizedDescription) } }
        }
    }
    func stop() { guard history.recording else { return }; history.captureBusy = true; recorder.stop(); statusChanged?("Finalisation…") }
    private func updateStatus() {
        guard let started, recorder.state == .recording else { return }
        let seconds = Int(Date().timeIntervalSince(started))
        statusChanged?(String(format: "%d:%02d", seconds/60, seconds%60))
    }
    private func finishedRecording(_ result: Result<URL, Error>) {
        ticker?.invalidate(); ticker = nil; started = nil; history.recording = false; history.captureBusy = true; statusChanged?("Enregistrement…")
        Task {
            defer { history.captureBusy = false; operation = nil; statusChanged?(nil) }
            do {
                let url = try result.get()
                let clip = try await history.saveVideo(url)
                try? FileManager.default.removeItem(at: url)
                let copied = await history.copy([clip]); showResult?()
                history.report(copied ? "Vidéo copiée · prête à coller dans une app compatible." : "Vidéo enregistrée. Ouvre l’aperçu pour la lire ou l’exporter.")
            } catch {
                showResult?(); history.report("Vidéo : " + error.localizedDescription)
                if let url = try? result.get(), FileManager.default.fileExists(atPath: url.path) {
                    let alert = NSAlert()
                    alert.messageText = "La vidéo est conservée sur ton Mac."
                    alert.informativeText = "L’ajout à l’historique a échoué : " + error.localizedDescription + "\nTu peux retrouver le fichier dans le Finder."
                    alert.addButton(withTitle: "Afficher le fichier"); alert.addButton(withTitle: "Plus tard")
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
    }
}
